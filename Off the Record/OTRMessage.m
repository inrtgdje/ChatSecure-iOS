//
//  OTRMessage.m
//  Off the Record
//
//  Created by David Chiles on 3/28/14.
//  Copyright (c) 2014 Chris Ballinger. All rights reserved.
//

#import "OTRMessage.h"
#import "OTRBuddy.h"
#import "OTRAccount.h"
#import "YapDatabaseTransaction.h"
#import "OTRDatabaseManager.h"
#import "YapDatabaseRelationshipTransaction.h"
#import "NSString+HTML.h"
#import "Strings.h"
#import "OTRConstants.h"

const struct OTRMessageAttributes OTRMessageAttributes = {
	.date = @"date",
	.text = @"text",
	.delivered = @"delivered",
	.read = @"read",
	.incoming = @"incoming",
    .messageId = @"messageId",
    .transportedSecurely = @"transportedSecurely"
};

const struct OTRMessageRelationships OTRMessageRelationships = {
	.buddyUniqueId = @"buddyUniqueId",
};

const struct OTRMessageEdges OTRMessageEdges = {
	.buddy = @"buddy",
};


@implementation OTRMessage

- (id)init
{
    if (self = [super init]) {
        self.date = [NSDate date];
        self.messageId = [[NSUUID UUID] UUIDString];
        self.delivered = NO;
        self.read = NO;
    }
    return self;
}

- (OTRBuddy *)buddyWithTransaction:(YapDatabaseReadTransaction *)readTransaction
{
    return [OTRBuddy fetchObjectWithUniqueID:self.buddyUniqueId transaction:readTransaction];
}

#pragma - mark YapDatabaseRelationshipNode

- (NSArray *)yapDatabaseRelationshipEdges
{
    NSArray *edges = nil;
    if (self.buddyUniqueId) {
        YapDatabaseRelationshipEdge *buddyEdge = [YapDatabaseRelationshipEdge edgeWithName:OTRMessageEdges.buddy
                                                                            destinationKey:self.buddyUniqueId
                                                                                collection:[OTRBuddy collection]
                                                                           nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
        
        edges = @[buddyEdge];
    }
    
    return edges;
    
}

#pragma mark NSCoding
- (instancetype)initWithCoder:(NSCoder *)decoder // NSCoding deserialization
{
    if (self = [super initWithCoder:decoder]) {
        self.date = [decoder decodeObjectForKey:OTRMessageAttributes.date];
        self.text = [decoder decodeObjectForKey:OTRMessageAttributes.text];
        self.delivered = [decoder decodeBoolForKey:OTRMessageAttributes.delivered];
        self.read = [decoder decodeBoolForKey:OTRMessageAttributes.read];
        self.incoming = [decoder decodeBoolForKey:OTRMessageAttributes.incoming];
        self.messageId = [decoder decodeObjectForKey:OTRMessageAttributes.messageId];
        self.transportedSecurely = [decoder decodeBoolForKey:OTRMessageAttributes.transportedSecurely];
        
        self.buddyUniqueId = [decoder decodeObjectForKey:OTRMessageRelationships.buddyUniqueId];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder // NSCoding serialization
{
    [super encodeWithCoder:encoder];
    
    [encoder encodeObject:self.date forKey:OTRMessageAttributes.date];
    [encoder encodeObject:self.text forKey:OTRMessageAttributes.text];
    [encoder encodeBool:self.delivered forKey:OTRMessageAttributes.delivered];
    [encoder encodeBool:self.read forKey:OTRMessageAttributes.read];
    [encoder encodeBool:self.incoming forKey:OTRMessageAttributes.incoming];
    [encoder encodeObject:self.messageId forKey:OTRMessageAttributes.messageId];
    [encoder encodeBool:self.transportedSecurely forKey:OTRMessageAttributes.transportedSecurely];
    
    [encoder encodeObject:self.buddyUniqueId forKey:OTRMessageRelationships.buddyUniqueId];
}

#pragma - mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    OTRMessage *copy = [super copyWithZone:zone];
    copy.date = [self.date copyWithZone:zone];
    copy.text = [self.text copyWithZone:zone];
    copy.delivered = self.delivered;
    copy.read = self.read;
    copy.incoming = self.incoming;
    copy.transportedSecurely = self.transportedSecurely;
    copy.messageId = [self.messageId copyWithZone:zone];
    copy.buddyUniqueId = [self.buddyUniqueId copyWithZone:zone];
    
    return copy;
}

#pragma - mark Class Methods

+ (NSInteger)numberOfUnreadMessagesWithTransaction:(YapDatabaseReadTransaction*)transaction
{
    __block int count = 0;
    [transaction enumerateKeysAndObjectsInCollection:[OTRMessage collection] usingBlock:^(NSString *key, OTRMessage *message, BOOL *stop) {
        if ([message isKindOfClass:[OTRMessage class]]) {
            if (!message.isRead) {
                count +=1;
            }
        }
    }];
    return count;
}

+ (void)deleteAllMessagesWithTransaction:(YapDatabaseReadWriteTransaction*)transaction
{
    [transaction removeAllObjectsInCollection:[OTRMessage collection]];
}

+ (void)deleteAllMessagesForBuddyId:(NSString *)uniqueBuddyId transaction:(YapDatabaseReadWriteTransaction*)transaction
{
    [[transaction ext:OTRYapDatabaseRelationshipName] enumerateEdgesWithName:OTRMessageEdges.buddy destinationKey:uniqueBuddyId collection:[OTRBuddy collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        [transaction removeObjectForKey:edge.sourceKey inCollection:edge.sourceCollection];
    }];
}

+ (void)deleteAllMessagesForAccountId:(NSString *)uniqueAccountId transaction:(YapDatabaseReadWriteTransaction*)transaction
{
    [[transaction ext:OTRYapDatabaseRelationshipName] enumerateEdgesWithName:OTRBuddyEdges.account destinationKey:uniqueAccountId collection:[OTRAccount collection] usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop) {
        [self deleteAllMessagesForBuddyId:edge.sourceKey transaction:transaction];
    }];
}

+ (void)receivedDeliveryReceiptForMessageId:(NSString *)messageId transaction:(YapDatabaseReadWriteTransaction*)transaction
{
    [transaction enumerateKeysAndObjectsInCollection:[OTRMessage collection] usingBlock:^(NSString *key, id object, BOOL *stop) {
        if ([object isKindOfClass:[OTRMessage class]]) {
            OTRMessage *message = (OTRMessage *)object;
            if ([message.messageId isEqualToString:messageId]) {
                message.delivered = YES;
                [transaction setObject:message forKey:message.uniqueId inCollection:[OTRMessage collection]];
                
                *stop = YES;
            }
        }
    }];
}

+ (void)showLocalNotificationForMessage:(OTRMessage *)message
{
    if (![[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
    {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString * rawMessage = [message.text stringByConvertingHTMLToPlainText];
            // We are not active, so use a local notification instead
            __block OTRBuddy *localBuddy = nil;
            __block OTRAccount *localAccount;
            [[OTRDatabaseManager sharedInstance].mainThreadReadOnlyDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                localBuddy = [message buddyWithTransaction:transaction];
                localAccount = [localBuddy accountWithTransaction:transaction];
                
            }];
            UILocalNotification *localNotification = [[UILocalNotification alloc] init];
            localNotification.alertAction = REPLY_STRING;
            localNotification.soundName = UILocalNotificationDefaultSoundName;
            localNotification.applicationIconBadgeNumber = [UIApplication sharedApplication].applicationIconBadgeNumber + 1;
            localNotification.alertBody = [NSString stringWithFormat:@"%@: %@",localBuddy.displayName,rawMessage];
            
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
            [userInfo setObject:localBuddy.username forKey:kOTRNotificationUserNameKey];
            [userInfo setObject:localAccount.username forKey:kOTRNotificationAccountNameKey];
            [userInfo setObject:@(localAccount.protocolType) forKey:kOTRNotificationProtocolKey];
            localNotification.userInfo = userInfo;
        
            [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
        });
    }
}

@end
