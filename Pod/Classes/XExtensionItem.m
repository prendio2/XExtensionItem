#import "XExtensionItem.h"
#import "XExtensionItemReferrer.h"
#import "XExtensionItemTypeSafeDictionaryValues.h"

static NSString * const ParameterKeyXExtensionItem = @"x-extension-item";
static NSString * const ParameterKeySourceURL = @"source-url";
static NSString * const ParameterKeyTags = @"tags";

@interface XExtensionItemSource ()

@property (nonatomic) id placeholderItem;
@property (nonatomic) NSString *dataTypeIdentifier;
@property (nonatomic) NSArray/*<NSItemProvider>*/ *attachments;

@property (nonatomic) NSMutableDictionary *activityTypesToItemProviderBlocks;
@property (nonatomic) NSMutableDictionary *activityTypesToSubjects;
@property (nonatomic) NSMutableDictionary *activityTypesToThumbnailProviderBlocks;

@end

@implementation XExtensionItemSource

#pragma mark - Initialization

- (instancetype)initWithPlaceholderItem:(id)placeholderItem attachments:(NSArray *)attachments {
    NSParameterAssert(placeholderItem);
    
    self = [super init];
    if (self) {
        _placeholderItem = placeholderItem;
        _attachments = [attachments copy];
        
        _activityTypesToItemProviderBlocks = [[NSMutableDictionary alloc] init];
        _activityTypesToSubjects = [[NSMutableDictionary alloc] init];
        _activityTypesToThumbnailProviderBlocks = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (instancetype)initWithPlaceholderData:(id)placeholderData
                     dataTypeIdentifier:(NSString *)dataTypeIdentifier
                            attachments:(NSArray/*<NSItemProvider>*/ *)attachments {
    NSParameterAssert(dataTypeIdentifier);
    
    self = [self initWithPlaceholderItem:placeholderData attachments:attachments];
    if (self) {
        _dataTypeIdentifier = [dataTypeIdentifier copy];
    }
    
    return self;
}

- (instancetype)init {
    return [self initWithPlaceholderItem:nil attachments:nil];
}

#pragma mark - XExtensionItemSource

- (void)addEntriesToUserInfo:(id <XExtensionItemDictionarySerializing>)dictionarySerializable {
    self.userInfo = ({
        NSMutableDictionary *mutableUserInfo = [[NSMutableDictionary alloc] initWithDictionary:self.userInfo];
        [mutableUserInfo addEntriesFromDictionary:dictionarySerializable.dictionaryRepresentation];
        mutableUserInfo;
    });
}

- (void)registerItemProvidingBlock:(XExtensionItemProvidingBlock)itemBlock forActivityType:(NSString *)activityType {
    NSParameterAssert(itemBlock);
    NSParameterAssert(activityType);
    
    if (activityType && itemBlock) {
        self.activityTypesToItemProviderBlocks[activityType] = itemBlock;
    }
}

- (void)registerSubject:(NSString *)subject forActivityType:(NSString *)activityType {
    NSParameterAssert(subject);
    NSParameterAssert(activityType);
    
    if (activityType && subject) {
        self.activityTypesToSubjects[activityType] = subject;
    }
}

- (void)registerThumbnailProvidingBlock:(XExtensionItemThumbnailProvidingBlock)thumbnailBlock forActivityType:(NSString *)activityType {
    NSParameterAssert(thumbnailBlock);
    NSParameterAssert(activityType);
    
    if (activityType && thumbnailBlock) {
        self.activityTypesToThumbnailProviderBlocks[activityType] = thumbnailBlock;
    }
}

#pragma mark - UIActivityItemSource

- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController {
    return self.placeholderItem;
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController
              subjectForActivityType:(NSString *)activityType {
    return self.activityTypesToSubjects[activityType];
}

- (UIImage *)activityViewController:(UIActivityViewController *)activityViewController
      thumbnailImageForActivityType:(NSString *)activityType
                      suggestedSize:(CGSize)size {
    XExtensionItemThumbnailProvidingBlock thumbnailBlock = self.activityTypesToThumbnailProviderBlocks[activityType];
    
    if (thumbnailBlock) {
        return thumbnailBlock(size);
    }
    else {
        return nil;
    }
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController dataTypeIdentifierForActivityType:(NSString *)activityType {
    return self.dataTypeIdentifier;
}

- (id)activityViewController:(UIActivityViewController *)activityViewController itemForActivityType:(NSString *)activityType {
    XExtensionItemProvidingBlock itemBlock = self.activityTypesToItemProviderBlocks[activityType];
    
    if (itemBlock) {
        return itemBlock();
    }
    else if (isExtensionItemInputAcceptedByActivityType(activityType)) {
        /*
         Share extensions take `NSExtensionItem` instances as input, and *some* system activities do as well, but some 
         do not. Unfortunately we need to maintain a hardcoded list of which system activities we can pass extension 
         items to.
         
         Trying to pass an extension item into a system activity that doesn’t know how to process it will result in no 
         data making it’s way through. In these cases, we’ll pass the placeholder item that this instance was 
         initialized with instead.
         */
        
        NSExtensionItem *item = [[NSExtensionItem alloc] init];
        item.userInfo = ({
            NSMutableDictionary *mutableUserInfo = [[NSMutableDictionary alloc] init];
            [mutableUserInfo addEntriesFromDictionary:self.userInfo];
            
            NSMutableDictionary *mutableParameters = [[NSMutableDictionary alloc] init];
            [mutableParameters setValue:self.tags forKey:ParameterKeyTags];
            [mutableParameters setValue:self.sourceURL forKey:ParameterKeySourceURL];
            [mutableParameters addEntriesFromDictionary:self.referrer.dictionaryRepresentation];
            
            if (mutableParameters.count > 0) {
                mutableUserInfo[ParameterKeyXExtensionItem] = [mutableParameters copy];
            }
            
            mutableUserInfo;
        });
        
        /*
         The `userInfo` setter *must* be called before the following three setters, which merely provide syntactic sugar for
         populating the `userInfo` dictionary with the following keys:
         
         * `NSExtensionItemAttributedTitleKey`,
         * `NSExtensionItemAttributedContentTextKey`
         * `NSExtensionItemAttachmentsKey`.
         
         */
        item.attachments = self.attachments;
        item.attributedTitle = self.attributedTitle;
        item.attributedContentText = self.attributedContentText;
        
        return item;
    }
    else {
        return self.placeholderItem;
    }
}

#pragma mark - Private

static BOOL isExtensionItemInputAcceptedByActivityType(NSString *activityType) {
    NSSet *unacceptingTypes = [[NSSet alloc] initWithArray:@[
                                                             UIActivityTypeMessage,
                                                             UIActivityTypeMail,
                                                             UIActivityTypePrint,
                                                             UIActivityTypeCopyToPasteboard,
                                                             UIActivityTypeAssignToContact,
                                                             UIActivityTypeSaveToCameraRoll,
                                                             UIActivityTypeAddToReadingList,
                                                             UIActivityTypeAirDrop,
                                                             ]];
    
    /*
     The following activities are capable of taking `NSExtensionItem` instances as input. They display system share 
     sheets that consume the extension item’s `attributedContentText` value.
     */
    NSSet *acceptingTypes = [[NSSet alloc] initWithArray:@[
                                                           UIActivityTypePostToTwitter,
                                                           UIActivityTypePostToVimeo,
                                                           UIActivityTypePostToWeibo,
                                                           UIActivityTypePostToTencentWeibo,
                                                           
                                                           /*
                                                            If the official Facebook or Flickr apps are installed, they 
                                                            take precedent over the system sheets and do *not* consume 
                                                            `attributedContentText`.
                                                            */
                                                           UIActivityTypePostToFacebook,
                                                           UIActivityTypePostToFlickr,
                                                           ]];
    
    if ([unacceptingTypes containsObject:activityType]) {
        return NO;
    }
    else if ([acceptingTypes containsObject:activityType]) {
        return YES;
    }
    else {
        return YES;
    }
}

@end


@interface XExtensionItem ()

@property (nonatomic) NSExtensionItem *extensionItem;
@property (nonatomic) NSExtensionItem *item;

@end

@implementation XExtensionItem

#pragma mark - Initialization

- (instancetype)initWithExtensionItem:(NSExtensionItem *)extensionItem {
    NSParameterAssert(extensionItem);
    
    self = [super init];
    if (self) {
        _extensionItem = extensionItem;
        
        NSDictionary *dictionary = [[[XExtensionItemTypeSafeDictionaryValues alloc] initWithDictionary:extensionItem.userInfo]
                                    dictionaryForKey:ParameterKeyXExtensionItem];
        
        XExtensionItemTypeSafeDictionaryValues *dictionaryValues = [[XExtensionItemTypeSafeDictionaryValues alloc] initWithDictionary:dictionary];
        
        _tags = [[dictionaryValues arrayForKey:ParameterKeyTags] copy];
        _sourceURL = [[dictionaryValues URLForKey:ParameterKeySourceURL] copy];
        _referrer = [[XExtensionItemReferrer alloc] initWithDictionary:dictionary];
    }
    
    return self;
}

- (instancetype)init {
    return [self initWithExtensionItem:nil];
}

#pragma mark - Proxied NSExtensionItem getters

- (NSArray *)attachments {
    return self.extensionItem.attachments;
}

- (NSAttributedString *)attributedTitle {
    return self.extensionItem.attributedTitle;
}

- (NSAttributedString *)attributedContentText {
    return self.extensionItem.attributedContentText;
}

- (NSDictionary *)userInfo {
    return self.extensionItem.userInfo;
}

#pragma mark - NSObject

- (NSString *)description {
    NSMutableString *mutableDescription = [[NSMutableString alloc] initWithFormat:@"%@ { attachments: %@",
                                           [super description], self.attachments];
    
    if (self.attributedTitle) {
        [mutableDescription appendFormat:@", attributedTitle: %@", self.attributedTitle];
    }
    
    if (self.attributedContentText) {
        [mutableDescription appendFormat:@", attributedContentText: %@", self.attributedContentText];
    }
    
    if (self.tags) {
        [mutableDescription appendFormat:@", tags: %@", self.tags];
    }
    
    if (self.sourceURL) {
        [mutableDescription appendFormat:@", sourceURL: %@", self.sourceURL];
    }
    
    if (self.referrer) {
        [mutableDescription appendFormat:@", sourceApplication: %@", self.referrer];
    }
    
    if (self.userInfo) {
        [mutableDescription appendFormat:@", userInfo: %@", ({
            NSMutableDictionary *mutableUserInfo = [self.userInfo mutableCopy];
            
            for (NSString *key in @[NSExtensionItemAttributedTitleKey, NSExtensionItemAttributedContentTextKey, NSExtensionItemAttachmentsKey]) {
                [mutableUserInfo removeObjectForKey:key];
            }
            
            // Remove values used internally by this class
            [mutableUserInfo removeObjectForKey:ParameterKeyXExtensionItem];
            
            [mutableUserInfo copy];
        })];
    }
    
    [mutableDescription appendFormat:@" }"];
    
    return [mutableDescription copy];
}

@end
