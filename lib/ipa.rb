require 'zip/zip'
require 'zip/zipfilesystem'
require 'cfpropertylist'

require 'zlib'
module IPA
	class IPAFile
		MAPPED_INFO_KEYS = {
			:name           => 'CFBundleName',
			:display_name   => 'CFBundleDisplayName',
			:identifier     => 'CFBundleIdentifier',
			:icon_path      => 'CFBundleIconFile',
			:icon_paths     => 'CFBundleIconFiles',
			:is_iphone      => 'LSRequiresIPhoneOS',
			:app_category   => 'LSApplicationCategoryType',
			:version        => 'CFBundleVersion',
			:version_string => 'CFBundleShortVersionString'
		}

		MAPPED_INFO_KEYS.each do |method_name, key_name|
			define_method method_name do
				info[key_name]
			end
		end

		def self.open(filename, &block)
			IPAFile.new(filename, &block)
		end

		def initialize(filename, &block)
			@zipfile = Zip::ZipFile.open(filename)
			unless block.nil?
				yield self
				close
			end
		end

		def close
			@zipfile.close
		end

       def self.normalize_png(oldPNG)
      pngheader = "\x89PNG\r\n\x1a\n"

      if oldPNG[0...8] != pngheader
        return nil
      end
    
      newPNG = oldPNG[0...8]
  
      chunkPos = newPNG.length
  
      # For each chunk in the PNG file
      while chunkPos < oldPNG.length
        
        # Reading chunk
        chunkLength = oldPNG[chunkPos...chunkPos+4]
        chunkLength = chunkLength.unpack("N")[0]
        chunkType = oldPNG[chunkPos+4...chunkPos+8]
        chunkData = oldPNG[chunkPos+8...chunkPos+8+chunkLength]
        chunkCRC = oldPNG[chunkPos+chunkLength+8...chunkPos+chunkLength+12]
        chunkCRC = chunkCRC.unpack("N")[0]
        chunkPos += chunkLength + 12

        # Parsing the header chunk
        if chunkType == "IHDR"
          width = chunkData[0...4].unpack("N")[0]
          height = chunkData[4...8].unpack("N")[0]
        end
    
        # Parsing the image chunk
        if chunkType == "IDAT"
          # Uncompressing the image chunk
          inf = Zlib::Inflate.new(-Zlib::MAX_WBITS)
          chunkData = inf.inflate(chunkData)
          inf.finish
          inf.close
  
          # Swapping red & blue bytes for each pixel
          newdata = ""
      
          height.times do 
            i = newdata.length
            newdata += chunkData[i..i].to_s
            width.times do
              i = newdata.length
              newdata += chunkData[i+2..i+2].to_s
              newdata += chunkData[i+1..i+1].to_s
              newdata += chunkData[i+0..i+0].to_s
              newdata += chunkData[i+3..i+3].to_s
            end
          end

          # Compressing the image chunk
          chunkData = newdata
          chunkData = Zlib::Deflate.deflate( chunkData )
          chunkLength = chunkData.length
          chunkCRC = Zlib.crc32(chunkType)
          chunkCRC = Zlib.crc32(chunkData, chunkCRC)
          chunkCRC = (chunkCRC + 0x100000000) % 0x100000000
        end
    
        # Removing CgBI chunk 
        if chunkType != "CgBI"
          newPNG += [chunkLength].pack("N")
          newPNG += chunkType
          if chunkLength > 0
            newPNG += chunkData
          end
          newPNG += [chunkCRC].pack("N")
        end

        # Stopping the PNG file parsing
        if chunkType == "IEND"
          break
        end
      end
   
      return newPNG
    end

		def payload_path(filename = nil)
			@payload_path ||= File.join('Payload',
				@zipfile.dir.entries('Payload').
				first{ |name| name =~ /\.app$/ })

			filename.nil? ? @payload_path : File.join(@payload_path, filename)
		end

		def payload_file(filename, &block)
			data = @zipfile.read(payload_path(filename))
			yield data unless block.nil?
		      if data
		        normalize_png(data)
      		end
		end

		def info
			if @info_plist.nil?
				data = payload_file('Info.plist')
				plist = CFPropertyList::List.new(:data => data)
				@info_plist = CFPropertyList.native_types(plist.value)
			end
			@info_plist
		end

		def icon
			path = info &&
				info['CFBundleIcons'] &&
				info['CFBundleIcons']['CFBundlePrimaryIcon'] &&
				(info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconFile'] ||
				 info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconFiles'].first)
			path ||= 'Icon.png'
			payload_file(path)
		end

		def artwork
			payload_file('iTunesArtwork')
		end
	end
end
