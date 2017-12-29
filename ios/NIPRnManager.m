//
//  NIPRnManager.m
//  NSIP
//
//  Created by 赵松 on 17/2/23.
//  Copyright © 2017年 netease. All rights reserved.
//

#import "NIPRnManager.h"
#import "NIPRnController.h"
#import "NIPRnUpdateService.h"
#import "NIPRnDefines.h"
#import "NIPRnHotReloadHelper.h"

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTBridge.h>
#else
#import "RCTBridge.h"
#endif

@interface NIPRnManager ()

/**
 *  根据bundle业务名称存储对应的bundle
 */
@property (nonatomic, strong) NSMutableDictionary *bundleDic;

@end


@implementation NIPRnManager

+ (instancetype)sharedManager
{
    return [self managerWithBundleUrl:nil noHotUpdate:NO noJsServer:NO];
}

+ (instancetype)managerWithBundleUrl:(NSString *)bundleUrl noHotUpdate:(BOOL)noHotUpdate noJsServer:(BOOL)noJsServer
{
    static dispatch_once_t predicate;
    static NIPRnManager *manager = nil;
    dispatch_once(&predicate, ^{
        manager = [[NIPRnManager alloc] init];
        manager.noHotUpdate = noHotUpdate;
        manager.noJsServer = noJsServer;
        if (hotreload_notEmptyString(bundleUrl)) {
            manager.bundleUrl = bundleUrl;
        } else {
#ifdef TEST_VERSION
            manager.bundleUrl = @"https://git.ms.netease.com/nsip_android/ftp/raw/master/rn_nsip_exchange_ios_source";
#else
            manager.bundleUrl =  @"https://img.hhtcex.com/product/api/client/resources/ios";
#endif
        }

        [manager initBridgeBundle];
    });
    return manager;
}

- (id)init {
    if (self = [super init]) {
        self.bundleDic = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark 根据业务获取bundle
- (RCTBridge *)getBridgeByBundleName:(NSString *)bundleName
{
    return [self.bundleDic objectForKey:bundleName];
}

/**
 *  获取当前app内存在的所有bundle
 *  首先获取位于docment沙河目录下的jsbundle文件
 *  然后获取位于app保内的jsbundle文件
 *  将文件的路径放在一个字典里，如果有重复以document优先
 */
- (void)initBridgeBundle
{
    
    NSArray *bundelArray = [self getAllBundles];
    [self loadBundleByNames:bundelArray];
}

- (void)loadBundleByNames:(NSArray *)bundleNames
{
    if (self.noJsServer) {
        for (NSString *bundelName in bundleNames) {
            NSURL *bundelPath = [self getJsLocationPath:bundelName];
            RCTBridge *bridge = [[RCTBridge alloc] initWithBundleURL:bundelPath
                                                      moduleProvider:nil
                                                       launchOptions:nil];
            [self.bundleDic setObject:bridge forKey:bundelName];
        }
    } else {
        NSURL *bundelPath = [self getJsLocationPath:@"index"];
        RCTBridge *bridge = [[RCTBridge alloc] initWithBundleURL:bundelPath
                                                  moduleProvider:nil
                                                   launchOptions:nil];
        if (bundleNames.count) {
            for (NSString *bundelName in bundleNames) {
                [self.bundleDic setObject:bridge forKey:bundelName];
            }
        } else {
            [self.bundleDic setObject:bridge forKey:@"index"];
        }
    }
}

- (void)loadBundleUnderDocument
{
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = [dirPaths objectAtIndex:0];
  
    NSMutableArray *filenamelist = [NSMutableArray arrayWithCapacity:10];
    NSArray *tmplist = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentPath error:nil];
    NSRange range;
    range.location = 0;
    NSInteger typeLength = [JSBUNDLE length] + 1;
    for (NSString *filename in tmplist) {
      if ([[filename pathExtension] isEqualToString:JSBUNDLE]) {
        range.length = filename.length - typeLength;
        NSString *nameWithoutExtension = [filename substringWithRange:range];
        [filenamelist addObject:nameWithoutExtension];
      }
    }
  
  NSArray *docmentBundleNames = filenamelist;
    [self loadBundleByNames:docmentBundleNames];
}

#pragma mark 目录处理

- (NSArray *)getAllBundles
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id localSDKInfo = [defaults objectForKey:RN_SDK_VERSION];
    id appBuildVersion = [defaults objectForKey:APP_BUILD_VERSION];
    if (!localSDKInfo || ![localSDKInfo isEqualToString:NIP_RN_SDK_VERSION]) {
        [self useDefaultRn];
    } else {
        if (!appBuildVersion || ![appBuildVersion isEqualToString:NIP_RN_BUILD_VERSION]) {
            [self useDefaultRn];
        }
    }
    
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = [dirPaths objectAtIndex:0];
    NSArray *docmentBundleNames = [NIPRnHotReloadHelper fileNameListOfType:JSBUNDLE fromDirPath:documentPath];
  
  
    if (!hotreload_notEmptyArray(docmentBundleNames)) {
        [self useDefaultRn];
    }
    docmentBundleNames = [NIPRnHotReloadHelper fileNameListOfType:JSBUNDLE fromDirPath:documentPath];
    NSString *mainBundlePath = [[NSBundle mainBundle] bundlePath];
  
  
    NSArray *mainBundles = [NIPRnHotReloadHelper fileNameListOfType:JSBUNDLE fromDirPath:mainBundlePath];
    
    NSMutableArray *array = [NSMutableArray arrayWithArray:docmentBundleNames];
    for (NSString *path in mainBundles) {
        if (![array containsObject:path]) {
            [array addObject:path];
        }
    }
    return array;
}

- (void)useDefaultRn {
    [self copyRnToLocal];
    [[NSUserDefaults standardUserDefaults] setObject:NIP_RN_DATA_VERSION forKey:RN_DATA_VERSION];
    [[NSUserDefaults standardUserDefaults] setObject:NIP_RN_SDK_VERSION forKey:RN_SDK_VERSION];
    [[NSUserDefaults standardUserDefaults] setObject:NIP_RN_BUILD_VERSION forKey:APP_BUILD_VERSION];
}

/// 缓存RN包到本地
- (void)copyRnToLocal {
    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *document = [docPaths objectAtIndex:0];
    NSString *bundlePath =  [document stringByAppendingPathComponent:@"index.jsbundle"];
    [NIPRnHotReloadHelper copyFile:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"jsbundle"] toPath:bundlePath];
    NSString *assetsPath =  [document stringByAppendingPathComponent:@"assets"];
    [NIPRnHotReloadHelper copyFolderFrom:[[NSBundle mainBundle] pathForResource:@"assets" ofType:nil] to:assetsPath];

//    for (NSString *fontName in self.fontNames) {
//        [NIPIconFontService copyFontToLocalWithName:fontName];
//    }
}

#pragma mark 加载rn controller

- (NIPRnController *)loadControllerWithModel:(NSString *)moduleName
{
    return [self loadWithBundleName:@"index" moduleName:moduleName];
}

- (NIPRnController *)loadWithBundleName:(NSString *)bundleName moduleName:(NSString *)moduleName
{
    NIPRnController *controller = [[NIPRnController alloc] initWithBundleName:bundleName moduleName:moduleName];
    return controller;
}

- (void)requestRCTAssetsBehind
{
    [[NIPRnUpdateService sharedService] requestRCTAssetsBehind];
}

#pragma mark 工具
//- (NIPRnController *)topMostController
//{
//    NIPRnController *controller = (NIPRnController *)[UIViewController topmostViewController];
//    if (!controller) {
//        controller = (NIPRnController *)[UIApplication sharedApplication].keyWindow.rootViewController;
//    }
//    return controller;
//}

- (NSString *)getJsServerIP
{
    NSString *serverIP = @"";
#if TARGET_OS_SIMULATOR
    serverIP = @"localhost";
#else
    serverIP = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SERVER_IP"];
#endif
    return serverIP;
}

- (NSURL *)getJsLocationPath:(NSString *)bundleName
{
    NSURL *jsCodeLocation = nil;
    if (self.noJsServer) {
        if (self.noHotUpdate) {
            jsCodeLocation = [[NSBundle mainBundle] URLForResource:bundleName withExtension:JSBUNDLE];
        } else {
            // 优先使用缓存的RN包
            NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *docsDir = [dirPaths objectAtIndex:0];
            NSString *bundelFullName = [NSString stringWithFormat:@"/%@.%@", bundleName, JSBUNDLE];
            NSString *jsBundlePath = [[NSString alloc] initWithString:[docsDir stringByAppendingPathComponent:bundelFullName]];
            jsCodeLocation = [NSURL URLWithString:jsBundlePath];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:jsBundlePath]) {
                jsCodeLocation = [[NSBundle mainBundle] URLForResource:bundleName withExtension:JSBUNDLE];
            }
        }
    } else {
        NSString *serverIP = [self getJsServerIP];
        NSString *jsCodeUrlString = [NSString stringWithFormat:@"http://%@:8081/%@.bundle?platform=ios&dev=true", serverIP, bundleName];
        jsCodeLocation = [NSURL URLWithString:jsCodeUrlString];
    }
    return jsCodeLocation;
}

#pragma mark - private method


#pragma mark js bridge
RCT_EXPORT_MODULE()

@end
