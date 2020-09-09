//
//  GVUserDefaults.m
//  GVUserDefaults
//
//  Created by Kevin Renskers on 18-12-12.
//  Copyright (c) 2012 Gangverk. All rights reserved.
//

#import "GVUserDefaults.h"
#import <objc/runtime.h>

@interface GVUserDefaults ()
@property (strong, nonatomic) NSString *initializedSuiteName;
@property (strong, nonatomic) NSMutableDictionary *mapping;
@property (strong, nonatomic) NSUserDefaults *userDefaults;
@end

@implementation GVUserDefaults

enum TypeEncodings {
    Char                = 'c',
    Bool                = 'B',
    Short               = 's',
    Int                 = 'i',
    Long                = 'l',
    LongLong            = 'q',
    UnsignedChar        = 'C',
    UnsignedShort       = 'S',
    UnsignedInt         = 'I',
    UnsignedLong        = 'L',
    UnsignedLongLong    = 'Q',
    Float               = 'f',
    Double              = 'd',
    Object              = '@'
};

- (NSUserDefaults *)userDefaults {
    if (!_userDefaults) {
        NSString *suiteName = nil;
        if ([NSUserDefaults instancesRespondToSelector:@selector(initWithSuiteName:)]) {
            suiteName = [self _suiteName];
        }

        if (suiteName && suiteName.length) {
            _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        } else {
            _userDefaults = [NSUserDefaults standardUserDefaults];
        }
    }

    return _userDefaults;
}

- (NSString *)defaultsKeyForPropertyNamed:(char const *)propertyName {
    NSString *key = [NSString stringWithFormat:@"%s", propertyName];
    return [self _transformKey:key];
}

- (NSString *)defaultsKeyForSelector:(SEL)selector {
    return [self.mapping objectForKey:NSStringFromSelector(selector)];
}

static long long longLongGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return [[self.userDefaults objectForKey:key] longLongValue];
}

static void longLongSetter(GVUserDefaults *self, SEL _cmd, long long value) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    NSNumber *object = [NSNumber numberWithLongLong:value];
    [self.userDefaults setObject:object forKey:key];
}

static bool boolGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return [self.userDefaults boolForKey:key];
}

static void boolSetter(GVUserDefaults *self, SEL _cmd, bool value) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    [self.userDefaults setBool:value forKey:key];
}

static int integerGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return (int)[self.userDefaults integerForKey:key];
}

static void integerSetter(GVUserDefaults *self, SEL _cmd, int value) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    [self.userDefaults setInteger:value forKey:key];
}

static float floatGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return [self.userDefaults floatForKey:key];
}

static void floatSetter(GVUserDefaults *self, SEL _cmd, float value) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    [self.userDefaults setFloat:value forKey:key];
}

static double doubleGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return [self.userDefaults doubleForKey:key];
}

static void doubleSetter(GVUserDefaults *self, SEL _cmd, double value) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    [self.userDefaults setDouble:value forKey:key];
}

static id objectGetter(GVUserDefaults *self, SEL _cmd) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    return [self.userDefaults objectForKey:key];
}

static void objectSetter(GVUserDefaults *self, SEL _cmd, id object) {
    NSString *key = [self defaultsKeyForSelector:_cmd];
    if (object) {
        [self.userDefaults setObject:object forKey:key];
    } else {
        [self.userDefaults removeObjectForKey:key];
    }
}

#pragma mark - Begin

+ (instancetype)standardUserDefaults {
    static dispatch_once_t pred;
    static GVUserDefaults *sharedInstance = nil;
    dispatch_once(&pred, ^{ sharedInstance = [[self alloc] init]; });
    return sharedInstance;
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wundeclared-selector"
#pragma GCC diagnostic ignored "-Warc-performSelector-leaks"

- (instancetype)initWithSuiteName:(NSString *)suiteName {
    self = [super init];
    if (self) {
        self.initializedSuiteName = suiteName;

        SEL setupDefaultSEL = NSSelectorFromString([NSString stringWithFormat:@"%@pDefaults", @"setu"]);
        if ([self respondsToSelector:setupDefaultSEL]) {
            NSDictionary *defaults = [self performSelector:setupDefaultSEL];
            NSMutableDictionary *mutableDefaults = [NSMutableDictionary dictionaryWithCapacity:[defaults count]];
            for (NSString *key in defaults) {
                id value = [defaults objectForKey:key];
                NSString *transformedKey = [self _transformKey:key];
                [mutableDefaults setObject:value forKey:transformedKey];
            }
            [self.userDefaults registerDefaults:mutableDefaults];
        }

        [self generateAccessorMethods];
    }

    return self;
}

- (instancetype)init {
    return [self initWithSuiteName:nil];
}

- (NSString *)_transformKey:(NSString *)key {
    if ([self respondsToSelector:@selector(transformKey:)]) {
        return [self performSelector:@selector(transformKey:) withObject:key];
    }

    return key;
}

- (NSString *)_suiteName {
    if (self.initializedSuiteName) {
        return self.initializedSuiteName;
    }

    // Backwards compatibility (v 1.0.0)
    if ([self respondsToSelector:@selector(suitName)]) {
        return [self performSelector:@selector(suitName)];
    }

    if ([self respondsToSelector:@selector(suiteName)]) {
        return [self performSelector:@selector(suiteName)];
    }

    return nil;
}

#pragma GCC diagnostic pop

- (void)generateAccessorMethods {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([self class], &count);

    // Properties that should not be mapped to user defaults but appear in the copied property list. (It would be more technically correct to trawl through the runtime, but this seems easier and faster.)
    static const char * const ignoredPropertyNames[] = {
        // NSObject protocol
        "hash",
        "superclass",
        "description",
        "debugDescription",
    };

    self.mapping = [NSMutableDictionary dictionary];

    for (int i = 0; i < count; ++i) {
        objc_property_t property = properties[i];

        const char *name = property_getName(property);
        BOOL skip = NO;
        for (int i = 0; i < (sizeof(ignoredPropertyNames) / sizeof(ignoredPropertyNames[0])); i++) {
            if (!strcmp(ignoredPropertyNames[i], name)) {
                skip = YES;
                break;
            }
        }
        if (skip) { continue; }

        const char *attributes = property_getAttributes(property);

        IMP getterImp = NULL;
        IMP setterImp = NULL;
        char type = attributes[1];
        switch (type) {
            case Short:
            case Long:
            case LongLong:
            case UnsignedChar:
            case UnsignedShort:
            case UnsignedInt:
            case UnsignedLong:
            case UnsignedLongLong:
                getterImp = (IMP)longLongGetter;
                setterImp = (IMP)longLongSetter;
                break;

            case Bool:
            case Char:
                getterImp = (IMP)boolGetter;
                setterImp = (IMP)boolSetter;
                break;

            case Int:
                getterImp = (IMP)integerGetter;
                setterImp = (IMP)integerSetter;
                break;

            case Float:
                getterImp = (IMP)floatGetter;
                setterImp = (IMP)floatSetter;
                break;

            case Double:
                getterImp = (IMP)doubleGetter;
                setterImp = (IMP)doubleSetter;
                break;

            case Object:
                getterImp = (IMP)objectGetter;
                setterImp = (IMP)objectSetter;
                break;

            default:
                continue;
        }

        char *getter = strstr(attributes, ",G");
        if (getter) {
            getter = strdup(getter + 2);
            getter = strsep(&getter, ",");
        } else {
            getter = strdup(name);
        }
        SEL getterSel = sel_registerName(getter);
        free(getter);

        char *setter = strstr(attributes, ",S");
        if (setter) {
            setter = strdup(setter + 2);
            setter = strsep(&setter, ",");
        } else {
            asprintf(&setter, "set%c%s:", toupper(name[0]), name + 1);
        }
        SEL setterSel = sel_registerName(setter);
        free(setter);

        NSString *key = [self defaultsKeyForPropertyNamed:name];
        [self.mapping setValue:key forKey:NSStringFromSelector(getterSel)];
        [self.mapping setValue:key forKey:NSStringFromSelector(setterSel)];

        char types[5];

        snprintf(types, 4, "%c@:", type);
        BOOL ok = class_addMethod([self class], getterSel, getterImp, types);
        NSAssert(ok, @"could not dynamically add getter for %1$s. Missing `@dynamic %1$s` in a .m file?", name);

        snprintf(types, 5, "v@:%c", type);
        ok = class_addMethod([self class], setterSel, setterImp, types);
        NSAssert(ok, @"could not dynamically add setter for %1$s. Missing `@dynamic %1$s` in a .m file?", name);
    }

    free(properties);
}

@end
