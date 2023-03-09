@implementation CacheSet

-(instancetype)initWithPathPrefix:(NSString*)prefix
{
	NSMutableArray<CacheFile*>* files=NSMutableArray.alloc.init.autorelease;
	
	CacheFile* file=[CacheFile.alloc initWithPath:prefix].autorelease;
	if(!file)
	{
		return nil;
	}
	
	[files addObject:file];
	
	// TODO: silly, can probably use dyld_subcache_entry
	
	for(NSString* format in @[@"%@.%d",@"%@.%02d"])
	{
		for(int index=1;;index++)
		{
			NSString* path=[NSString stringWithFormat:format,prefix,index];
			
			CacheFile* file=[CacheFile.alloc initWithPath:path].autorelease;
			if(!file)
			{
				break;
			}
			
			[files addObject:file];
		}
	}
	
	if(files.count==0)
	{
		return nil;
	}
	
	self.files=files;
	
	trace(@"os version %d.%d.%d",self.majorVersion,self.minorVersion,self.subMinorVersion);
	
	return self;
}

-(int)majorVersion
{
	return self.files[0].header->osVersion/0x10000;
}

-(int)minorVersion
{
	return (self.files[0].header->osVersion/0x100)%0x100;
}

-(int)subMinorVersion
{
	return self.files[0].header->osVersion%0x100;
}

-(long)addressWithOffset:(long)offset
{
	// lacks context of which cache file
	
	abort();
}

-(long)addressWithPointer:(char*)pointer
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapPointerUnsafe(file,pointer);
		if(location)
		{
			return location.address;
		}
	}
	
	return -1;
}

-(long)offsetWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapAddressUnsafe(file,address);
		if(location)
		{
			return location.offset;
		}
	}
	
	return -1;
}

-(char*)pointerWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		Location* location=wrapAddressUnsafe(file,address);
		if(location)
		{
			return location.pointer;
		}
	}
	
	return NULL;
}

-(CacheImage*)imageWithPath:(NSString*)path
{
	for(CacheFile* file in self.files)
	{
		CacheImage* image=[file imageWithPath:path];
		if(image)
		{
			return image;
		}
	}
	
	return nil;
}

-(NSArray<CacheImage*>*)imagesWithPathPrefix:(NSString*)path
{
	NSMutableArray<CacheImage*>* result=NSMutableArray.alloc.init.autorelease;
	
	for(CacheFile* file in self.files)
	{
		NSArray<CacheImage*>* images=[file imagesWithPathPrefix:path];
		[result addObjectsFromArray:images];
	}
	
	return result;
}

-(CacheImage*)imageWithAddress:(long)address
{
	for(CacheFile* file in self.files)
	{
		CacheImage* image=[file imageWithAddress:address];
		if(image)
		{
			return image;
		}
	}
	
	return nil;
}

@end