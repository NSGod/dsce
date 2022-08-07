@implementation CacheFile

-(instancetype)initWithPath:(NSString*)path
{
	self=super.init;
	
	self.data=[NSMutableData dataWithContentsOfFile:path];
	if(!self.data)
	{
		return nil;
	}
	
	self.header=(struct dyld_cache_header*)self.data.bytes;
	
	self.loadImages;
	self.loadRebases;
	
	trace(@"loaded %@ (%x images, %x rebases)",path,self.images.count,self.rebaseAddresses.count);
	
	return self;
}

-(void)forEachMapping:(void (^)(struct dyld_cache_mapping_and_slide_info*))block
{
	// using Location here would create a circular dependency
	
	struct dyld_cache_mapping_and_slide_info* infos=(struct dyld_cache_mapping_and_slide_info*)((char*)self.data.mutableBytes+self.header->mappingWithSlideOffset);
	for(int index=0;index<self.header->mappingWithSlideCount;index++)
	{
		block(&infos[index]);
	}
}

-(long)addressWithOffset:(long)offset
{
	__block dyld_cache_mapping_and_slide_info* info=NULL;
	
	[self forEachMapping:^(struct dyld_cache_mapping_and_slide_info* mapping)
	{
		if(offset>=mapping->fileOffset&&offset<mapping->fileOffset+mapping->size)
		{
			assert(!info);
			info=mapping;
		}
	}];
	
	if(!info)
	{
		return -1;
	}
	
	return info->address+offset-info->fileOffset;
}

-(long)addressWithPointer:(char*)pointer
{
	return [self addressWithOffset:pointer-(char*)self.data.mutableBytes];
}

-(long)offsetWithAddress:(long)address
{
	__block dyld_cache_mapping_and_slide_info* info=NULL;
	
	[self forEachMapping:^(struct dyld_cache_mapping_and_slide_info* mapping)
	{
		if(address>=mapping->address&&address<mapping->address+mapping->size)
		{
			assert(!info);
			info=mapping;
		}
	}];
	
	if(!info)
	{
		return -1;
	}
	
	return info->fileOffset+address-info->address;
}

-(char*)pointerWithAddress:(long)address
{
	long offset=[self offsetWithAddress:address];
	if(offset==-1)
	{
		return NULL;
	}
	
	return (char*)self.data.mutableBytes+offset;
}

-(void)loadImages
{
	NSMutableArray<Image*>* images=NSMutableArray.alloc.init.autorelease;
	
	struct dyld_cache_image_info* infos=(struct dyld_cache_image_info*)wrapOffset(self,self.header->imagesOffset).pointer;
	
	for(int index=0;index<self.header->imagesCount;index++)
	{
		Image* image=[Image.alloc initWithCacheFile:self info:&infos[index]].autorelease;
		if(image)
		{
			[images addObject:image];
		}
	}
	
	self.images=images;
}

-(void)loadRebases
{
	NSMutableArray<NSNumber*>* addresses=NSMutableArray.alloc.init.autorelease;
	
	[self forEachMapping:^(struct dyld_cache_mapping_and_slide_info* mapping)
	{
		if(mapping->slideInfoFileOffset)
		{
			dyld_cache_slide_info2* slide=(struct dyld_cache_slide_info2*)wrapOffset(self,mapping->slideInfoFileOffset).pointer;
			assert(slide->version==2);
			
			// dyld_cache_format.h
			
			unsigned long valueMask=~(slide->delta_mask);
			int deltaShift=__builtin_ctzll(slide->delta_mask)-2;
			
			short* starts=(short*)((char*)slide+slide->page_starts_offset);
			for(long pageIndex=0;pageIndex<slide->page_starts_count;pageIndex++)
			{
				if(starts[pageIndex]==DYLD_CACHE_SLIDE_PAGE_ATTR_NO_REBASE)
				{
					continue;
				}
				
				assert((starts[pageIndex]&DYLD_CACHE_SLIDE_PAGE_ATTR_EXTRA)==0);
				
				unsigned long startAddress=mapping->address+pageIndex*slide->page_size+starts[pageIndex]*4;
				char* pointer=wrapAddress(self,startAddress).pointer;
				
				int delta=1;
				while(delta)
				{
					unsigned long* valuePointer=(unsigned long*)pointer;
					delta=(*valuePointer&slide->delta_mask)>>deltaShift;
					
					unsigned long value=(*valuePointer&valueMask)+slide->value_add;
					*valuePointer=value;
					
					unsigned long address=wrapPointer(self,pointer).address;
					[addresses addObject:[NSNumber numberWithLong:address]];
					
					pointer+=delta;
				}
			}
		}
	}];
	
	// TODO: may be unnecessary
	
	[addresses sortUsingComparator:^NSComparisonResult(NSNumber* first,NSNumber* second)
	{
		return first.longValue<second.longValue?NSOrderedAscending:NSOrderedDescending;
	}];
	
	self.rebaseAddresses=addresses;
}

-(NSArray<Image*>*)imagesWithPathPrefix:(NSString*)path
{
	NSMutableArray<Image*>* result=NSMutableArray.alloc.init.autorelease;
	
	for(Image* image in self.images)
	{
		if([image.path hasPrefix:path])
		{
			[result addObject:image];
		}
	}
	
	return result;
}

-(Image*)imageWithAddress:(long)address
{
	for(Image* image in self.images)
	{
		if([image.header segmentCommandWithAddress:address indexOut:NULL])
		{
			return image;
		}
	}
	
	return nil;
}

@end