// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXAppState.h"
#import "EXDevSettings.h"
#import "EXDisabledDevLoadingView.h"
#import "EXDisabledDevMenu.h"
#import "EXDisabledRedBox.h"
#import "EXFileSystem.h"
#import "EXVersionManager.h"
#import "EXScopedBridgeModule.h"
#import "EXStatusBarManager.h"
#import "EXUnversioned.h"
#import "EXScopedFileSystemModule.h"
#import "EXTest.h"

#import <React/RCTAssert.h>
#import <React/RCTBridge.h>
#import <React/RCTBridge+Private.h>
#import <React/RCTDevMenu.h>
#import <React/RCTDevSettings.h>
#import <React/RCTExceptionsManager.h>
#import <React/RCTLog.h>
#import <React/RCTRedBox.h>
#import <React/RCTModuleData.h>
#import <React/RCTUtils.h>

#import <React/RCTAsyncLocalStorage.h>

#import <objc/message.h>

#import <UMFileSystemInterface/UMFileSystemInterface.h>
#import <UMCore/UMModuleRegistry.h>
#import <UMCore/UMModuleRegistryDelegate.h>
#import <UMReactNativeAdapter/UMNativeModulesProxy.h>
#import "EXScopedModuleRegistryAdapter.h"
#import "EXScopedModuleRegistryDelegate.h"

// used for initializing scoped modules which don't tie in to any kernel service.
#define EX_KERNEL_SERVICE_NONE @"EXKernelServiceNone"

// this is needed because RCTPerfMonitor does not declare a public interface
// anywhere that we can import.
@interface RCTPerfMonitorDevSettingsHack <NSObject>

- (void)hide;
- (void)show;

@end

static NSMutableDictionary<NSString *, NSDictionary *> *EXScopedModuleClasses;
void EXRegisterScopedModule(Class, ...);
void EXRegisterScopedModule(Class moduleClass, ...)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    EXScopedModuleClasses = [NSMutableDictionary dictionary];
  });
  
  NSString *kernelServiceClassName;
  va_list argumentList;
  NSMutableDictionary *unversionedKernelServiceClassNames = [[NSMutableDictionary alloc] init];
  
  va_start(argumentList, moduleClass);
    while ((kernelServiceClassName = va_arg(argumentList, NSString*))) {
      if ([kernelServiceClassName isEqualToString:@"nil"]) {
        unversionedKernelServiceClassNames[kernelServiceClassName] = EX_KERNEL_SERVICE_NONE;
      } else {
        unversionedKernelServiceClassNames[kernelServiceClassName] = [EX_UNVERSIONED(@"EX") stringByAppendingString:kernelServiceClassName];
      }
    }
  va_end(argumentList);
  
  NSString *moduleClassName = NSStringFromClass(moduleClass);
  if (moduleClassName) {
    EXScopedModuleClasses[moduleClassName] = unversionedKernelServiceClassNames;
  }
}

@interface RCTBridgeHack <NSObject>

- (void)reload;

@end

@interface EXVersionManager ()

// is this the first time this ABI has been touched at runtime?
@property (nonatomic, assign) BOOL isFirstLoad;

@end

@implementation EXVersionManager

- (instancetype)initWithFatalHandler:(void (^)(NSError *))fatalHandler
                         logFunction:(void (^)(NSInteger, NSInteger, NSString *, NSNumber *, NSString *))logFunction
                        logThreshold:(NSInteger)threshold
{
  if (self = [super init]) {
    [self configureABIWithFatalHandler:fatalHandler logFunction:logFunction logThreshold:threshold];
  }
  return self;
}

- (void)bridgeWillStartLoading:(id)bridge
{
  // Override the "Reload" button from Redbox to reload the app from manifest
  // Keep in mind that it is possible this will return a EXDisabledRedBox
  RCTRedBox *redBox = [self _moduleInstanceForBridge:bridge named:@"RedBox"];
  [redBox setOverrideReloadAction:^{
      [[NSNotificationCenter defaultCenter]
     postNotificationName:EX_UNVERSIONED(@"EXReloadActiveAppRequest") object:nil];
  }];

  // Manually send a "start loading" notif, since the real one happened uselessly inside the RCTBatchedBridge constructor
  [[NSNotificationCenter defaultCenter]
   postNotificationName:RCTJavaScriptWillStartLoadingNotification object:bridge];
}

- (void)bridgeFinishedLoading {

}

- (void)invalidate
{

}

- (NSDictionary<NSString *, NSString *> *)devMenuItemsForBridge:(id)bridge
{
  RCTDevSettings *devSettings = [self _moduleInstanceForBridge:bridge named:@"DevSettings"];
  BOOL isDevModeEnabled = [self _isDevModeEnabledForBridge:bridge];
  NSMutableDictionary *items = [@{
    @"dev-inspector": @{ @"label": @"Toggle Element Inspector", @"isEnabled": isDevModeEnabled ? @YES : @NO },
  } mutableCopy];
  if (devSettings.isRemoteDebuggingAvailable && isDevModeEnabled) {
    items[@"dev-remote-debug"] = @{
      @"label": (devSettings.isDebuggingRemotely) ? @"Stop Remote Debugging" : @"Debug Remote JS",
      @"isEnabled": @YES
    };
  } else {
    items[@"dev-remote-debug"] =  @{ @"label": @"Remote Debugger Unavailable", @"isEnabled": @NO };
  }

  if (devSettings.isHotLoadingAvailable && isDevModeEnabled) {
    items[@"dev-hmr"] = @{
      @"label": (devSettings.isHotLoadingEnabled) ? @"Disable Fast Refresh" : @"Enable Fast Refresh",
      @"isEnabled": @YES,
    };
  } else {
    NSMutableDictionary *hmrItem = [@{
      @"label": @"Fast Refresh Unavailable",
      @"isEnabled": @NO,
      @"detail": @"Use the Reload button above to reload when in production mode. Switch back to development mode to use Fast Refresh."
    } mutableCopy];
    items[@"dev-hmr"] =  hmrItem;
  }

  id perfMonitor = [self _moduleInstanceForBridge:bridge named:@"PerfMonitor"];
  if (perfMonitor) {
    items[@"dev-perf-monitor"] = @{
      @"label": devSettings.isPerfMonitorShown ? @"Hide Performance Monitor" : @"Show Performance Monitor",
      @"isEnabled": isDevModeEnabled ? @YES : @NO,
    };
  }

  return items;
}

- (void)selectDevMenuItemWithKey:(NSString *)key onBridge:(id)bridge
{
  RCTAssertMainQueue();
  RCTDevSettings *devSettings = [self _moduleInstanceForBridge:bridge named:@"DevSettings"];
  if ([key isEqualToString:@"dev-reload"]) {
    // bridge could be an RCTBridge of any version and we need to cast it since ARC needs to know
    // the return type
    [(RCTBridgeHack *)bridge reload];
  } else if ([key isEqualToString:@"dev-remote-debug"]) {
    devSettings.isDebuggingRemotely = !devSettings.isDebuggingRemotely;
  } else if ([key isEqualToString:@"dev-profiler"]) {
    devSettings.isProfilingEnabled = !devSettings.isProfilingEnabled;
  } else if ([key isEqualToString:@"dev-hmr"]) {
    devSettings.isHotLoadingEnabled = !devSettings.isHotLoadingEnabled;
  } else if ([key isEqualToString:@"dev-inspector"]) {
    [devSettings toggleElementInspector];
  } else if ([key isEqualToString:@"dev-perf-monitor"]) {
    id perfMonitor = [self _moduleInstanceForBridge:bridge named:@"PerfMonitor"];
    if (perfMonitor) {
      if (devSettings.isPerfMonitorShown) {
        [perfMonitor hide];
        devSettings.isPerfMonitorShown = NO;
      } else {
        [perfMonitor show];
        devSettings.isPerfMonitorShown = YES;
      }
    }
  }
}

- (void)showDevMenuForBridge:(id)bridge
{
  RCTAssertMainQueue();
  id devMenu = [self _moduleInstanceForBridge:bridge named:@"DevMenu"];
  // respondsToSelector: check is required because it's possible this bridge
  // was instantiated with a `disabledDevMenu` instance and the gesture preference was recently updated.
  if ([devMenu respondsToSelector:@selector(show)]) {
    [((RCTDevMenu *)devMenu) show];
  }
}

- (void)disableRemoteDebuggingForBridge:(id)bridge
{
  RCTDevSettings *devSettings = [self _moduleInstanceForBridge:bridge named:@"DevSettings"];
  devSettings.isDebuggingRemotely = NO;
}

- (void)toggleElementInspectorForBridge:(id)bridge
{
  RCTDevSettings *devSettings = [self _moduleInstanceForBridge:bridge named:@"DevSettings"];
  [devSettings toggleElementInspector];
}


#pragma mark - internal

- (BOOL)_isDevModeEnabledForBridge:(id)bridge
{
  return ([RCTGetURLQueryParam([bridge bundleURL], @"dev") boolValue]);
}

- (id<RCTBridgeModule>)_moduleInstanceForBridge:(id)bridge named:(NSString *)name
{
  if ([bridge respondsToSelector:@selector(batchedBridge)]) {
    bridge = [bridge batchedBridge];
  }
  RCTModuleData *data = [bridge moduleDataForName:name];
  if (data) {
    return [data instance];
  }
  return nil;
}

- (void)configureABIWithFatalHandler:(void (^)(NSError *))fatalHandler
                         logFunction:(void (^)(NSInteger, NSInteger, NSString *, NSNumber *, NSString *))logFunction
                        logThreshold:(NSInteger)threshold
{
  RCTSetFatalHandler(fatalHandler);
  RCTSetLogThreshold(threshold);
  RCTSetLogFunction(logFunction);
}

/**
 *  Expected params:
 *    NSDictionary *manifest
 *    NSDictionary *constants
 *    NSURL *initialUri
 *    @BOOL isDeveloper
 *    @BOOL isStandardDevMenuAllowed
 *    @EXTestEnvironment testEnvironment
 *    NSDictionary *services
 *
 * Kernel-only:
 *    EXKernel *kernel
 *    NSArray *supportedSdkVersions
 *    id exceptionsManagerDelegate
 */
- (NSArray *)extraModulesWithParams:(NSDictionary *)params
{
  BOOL isDeveloper = [params[@"isDeveloper"] boolValue];
  NSDictionary *manifest = params[@"manifest"];
  NSString *experienceId = manifest[@"id"];
  NSDictionary *services = params[@"services"];
  BOOL isOpeningHomeInProductionMode = params[@"browserModuleClass"] && !manifest[@"developer"];

  NSMutableArray *extraModules = [NSMutableArray arrayWithArray:
                                  @[
                                    [[EXAppState alloc] init],
                                    [[EXDevSettings alloc] initWithExperienceId:experienceId isDevelopment:(!isOpeningHomeInProductionMode && isDeveloper)],
                                    [[EXDisabledDevLoadingView alloc] init],
                                    [[EXStatusBarManager alloc] init],
                                    ]];
  
  // add scoped modules
  [extraModules addObjectsFromArray:[self _newScopedModulesWithExperienceId:experienceId services:services params:params]];

  id exceptionsManagerDelegate = params[@"exceptionsManagerDelegate"];
  if (exceptionsManagerDelegate) {
    RCTExceptionsManager *exceptionsManager = [[RCTExceptionsManager alloc] initWithDelegate:exceptionsManagerDelegate];
    [extraModules addObject:exceptionsManager];
  } else {
    RCTLogWarn(@"No exceptions manager provided when building extra modules for bridge.");
  }
  
  if (params[@"testEnvironment"]) {
    EXTestEnvironment testEnvironment = (EXTestEnvironment)[params[@"testEnvironment"] unsignedIntegerValue];
    if (testEnvironment != EXTestEnvironmentNone) {
      EXTest *testModule = [[EXTest alloc] initWithEnvironment:testEnvironment];
      [extraModules addObject:testModule];
    }
  }
  
  if (params[@"browserModuleClass"]) {
    Class browserModuleClass = params[@"browserModuleClass"];
    id homeModule = [[browserModuleClass alloc] initWithExperienceId:experienceId
                                                    kernelServiceDelegate:services[EX_UNVERSIONED(@"EXHomeModuleManager")]
                                                                   params:params];
    [extraModules addObject:homeModule];
  }

  if ([params[@"isStandardDevMenuAllowed"] boolValue] && isDeveloper) {
    [extraModules addObject:[[RCTDevMenu alloc] init]];
  } else {
    // non-kernel, or non-development kernel, uses expo menu instead of RCTDevMenu
    [extraModules addObject:[[EXDisabledDevMenu alloc] init]];
  }
  if (!isDeveloper) {
    // user-facing (not debugging).
    // additionally disable RCTRedBox
    [extraModules addObject:[[EXDisabledRedBox alloc] init]];
  }

  UMModuleRegistryProvider *moduleRegistryProvider = [[UMModuleRegistryProvider alloc] initWithSingletonModules:params[@"singletonModules"]];

  Class resolverClass = [EXScopedModuleRegistryDelegate class];
  if (params[@"moduleRegistryDelegateClass"] && params[@"moduleRegistryDelegateClass"] != [NSNull null]) {
    resolverClass = params[@"moduleRegistryDelegateClass"];
  }

  id<UMModuleRegistryDelegate> moduleRegistryDelegate = [[resolverClass alloc] initWithParams:params];
  [moduleRegistryProvider setModuleRegistryDelegate:moduleRegistryDelegate];

  EXScopedModuleRegistryAdapter *moduleRegistryAdapter = [[EXScopedModuleRegistryAdapter alloc] initWithModuleRegistryProvider:moduleRegistryProvider];
  UMModuleRegistry *moduleRegistry = [moduleRegistryAdapter moduleRegistryForParams:params forExperienceId:experienceId withKernelServices:services];
  NSArray<id<RCTBridgeModule>> *expoModules = [moduleRegistryAdapter extraModulesForModuleRegistry:moduleRegistry];
  [extraModules addObjectsFromArray:expoModules];

  id<UMFileSystemInterface> fileSystemModule = [moduleRegistry getModuleImplementingProtocol:@protocol(UMFileSystemInterface)];
  NSString *localStorageDirectory = [fileSystemModule.documentDirectory stringByAppendingPathComponent:EX_UNVERSIONED(@"RCTAsyncLocalStorage")];
  [extraModules addObject:[[RCTAsyncLocalStorage alloc] initWithStorageDirectory:localStorageDirectory]];

  return extraModules;
}

- (NSArray *)_newScopedModulesWithExperienceId: (NSString *)experienceId services:(NSDictionary *)services params:(NSDictionary *)params
{
  NSMutableArray *result = [NSMutableArray array];
  if (EXScopedModuleClasses) {
    [EXScopedModuleClasses enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull scopedModuleClassName, NSDictionary * _Nonnull kernelServiceClassNames, BOOL * _Nonnull stop) {
      NSMutableDictionary *moduleServices = [[NSMutableDictionary alloc] init];
      for (id kernelServiceClassName in kernelServiceClassNames) {
        NSString *kernelSerivceName = kernelServiceClassNames[kernelServiceClassName];
        id service = ([kernelSerivceName isEqualToString:EX_KERNEL_SERVICE_NONE]) ? [NSNull null] : services[kernelSerivceName];
        moduleServices[kernelServiceClassName] = service;
      }
      
      id scopedModule;
      Class scopedModuleClass = NSClassFromString(scopedModuleClassName);
      if (moduleServices.count > 1) {
        scopedModule = [[scopedModuleClass alloc] initWithExperienceId:experienceId kernelServiceDelegates:moduleServices params:params];
      } else if (moduleServices.count == 0) {
        scopedModule = [[scopedModuleClass alloc] initWithExperienceId:experienceId kernelServiceDelegate:nil params:params];
      } else {
        scopedModule = [[scopedModuleClass alloc] initWithExperienceId:experienceId kernelServiceDelegate:moduleServices[[moduleServices allKeys][0]] params:params];
      }
      
      if (scopedModule) {
        [result addObject:scopedModule];
      }
    }];
  }
  return result;
}

@end
