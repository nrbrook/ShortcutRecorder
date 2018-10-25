//
//  SRRecorderControl.m
//  ShortcutRecorder
//
//  Copyright 2006-2012 Contributors. All rights reserved.
//
//  License: BSD
//
//  Contributors:
//      David Dauer
//      Jesper
//      Jamie Kirkpatrick
//      Ilya Kulakov

#include <limits.h>

#import "SRRecorderControl.h"
#import "SRKeyCodeTransformer.h"
#import "SRModifierFlagsTransformer.h"


NSString *const SRShortcutKeyCode = @"keyCode";

NSString *const SRShortcutModifierFlagsKey = @"modifierFlags";

NSString *const SRShortcutCharacters = @"characters";

NSString *const SRShortcutCharactersIgnoringModifiers = @"charactersIgnoringModifiers";


// Control Layout Constants

typedef struct {
    CGSize size;
    CGFloat rightOffset;
    CGFloat leftOffset;
} SRRecorderButtonDimensions;

typedef struct {
    CGFloat shapeXRadius;
    CGFloat shapeYRadius;
    CGFloat height;
    CGFloat inset;
    CGFloat bottomShadowHeight;
    SRRecorderButtonDimensions clearButton;
    SRRecorderButtonDimensions snapBackButton;
} SRRecorderControlDimensions;

static const SRRecorderControlDimensions SRRecorderYosemiteDimensions = {
    .shapeXRadius = 2.0,
    .shapeYRadius = 2.0,
    .height = 25.0,
    .inset = 1.0,
    .bottomShadowHeight = 1.0,
    .clearButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 4.0,
        .leftOffset = 1.0,
    },
    .snapBackButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 1.0,
        .leftOffset = 3.0,
    }
};

static const SRRecorderControlDimensions SRRecorderElCapitanDimensions = {
    .shapeXRadius = 4.5,
    .shapeYRadius = 4.5,
    .height = 25.0,
    .inset = 1.0,
    .bottomShadowHeight = 1.0,
    .clearButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 4.0,
        .leftOffset = 1.0,
    },
    .snapBackButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 1.0,
        .leftOffset = 3.0,
    }
};

static const SRRecorderControlDimensions SRRecorderMojaveDimensions = {
    .shapeXRadius = 4.5,
    .shapeYRadius = 4.5,
    .height = 25.0,
    .inset = 1.0,
    .bottomShadowHeight = 1.0,
    .clearButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 4.0,
        .leftOffset = 1.0,
    },
    .snapBackButton = {
        .size = {
            .width = 14.0,
            .height = 14.0,
        },
        .rightOffset = 1.0,
        .leftOffset = 3.0,
    }
};

// TODO: see baselineOffsetFromBottom
// static const CGFloat _SRRecorderControlBaselineOffset = 5.0;

NSAppearanceName _SRLoadedAppearanceName = nil;
static const SRRecorderControlDimensions * _SRControlDimensions;
static NSString * _SRImageNamePrefix = nil;

typedef struct {
    NSImage * left;
    NSImage * middle;
    NSImage * right;
} SRRecorderBezelImages;
static struct {
    struct {
        struct {
            SRRecorderBezelImages blue;
            SRRecorderBezelImages graphite;
        } highlighted;
        SRRecorderBezelImages normal;
        SRRecorderBezelImages editing;
        SRRecorderBezelImages disabled;
    } bezel;
    struct {
        NSImage * normal;
        NSImage * highlighted;
    } clear;
    struct {
        NSImage * normal;
        NSImage * highlighted;
    } snapback;
} _SRImages;

typedef NS_ENUM(NSUInteger, _SRRecorderControlButtonTag)
{
    _SRRecorderControlInvalidButtonTag = -1,
    _SRRecorderControlSnapBackButtonTag = 0,
    _SRRecorderControlClearButtonTag = 1,
    _SRRecorderControlMainButtonTag = 2
};


@implementation SRRecorderControl
{
    NSTrackingArea *_mainButtonTrackingArea;
    NSTrackingArea *_snapBackButtonTrackingArea;
    NSTrackingArea *_clearButtonTrackingArea;

    _SRRecorderControlButtonTag _mouseTrackingButtonTag;
    NSToolTipTag _snapBackButtonToolTipTag;
}

+ (void)initialize
{
    if (self == [SRRecorderControl class]) {
        [self exposeBinding:NSValueBinding];
        [self exposeBinding:NSEnabledBinding];
        
        if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_10)
        {
            _SRImageNamePrefix = @"shortcut-recorder-yosemite-";
            _SRControlDimensions = &SRRecorderYosemiteDimensions;
        } else if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_13) {
            _SRImageNamePrefix = @"shortcut-recorder-el-capitan-";
            _SRControlDimensions = &SRRecorderElCapitanDimensions;
        } else {
            _SRImageNamePrefix = @"shortcut-recorder-mojave-";
            _SRControlDimensions = &SRRecorderMojaveDimensions;
        }
    }
}

- (instancetype)initWithFrame:(NSRect)aFrameRect
{
    self = [super initWithFrame:aFrameRect];

    if (self)
    {
        [self _initInternalState];
    }

    return self;
}

- (void)_initInternalState
{
    _allowsEmptyModifierFlags = NO;
    _drawsASCIIEquivalentOfShortcut = YES;
    _allowsEscapeToCancelRecording = YES;
    _allowsDeleteToClearShortcutAndEndRecording = YES;
    _enabled = YES;
    _allowedModifierFlags = SRCocoaModifierFlagsMask;
    _requiredModifierFlags = 0;
    _mouseTrackingButtonTag = _SRRecorderControlInvalidButtonTag;
    _snapBackButtonToolTipTag = NSIntegerMax;

    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
    {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationVertical];

        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationVertical];
    }

    self.toolTip = SRLoc(@"Click to record shortcut");
    [self updateTrackingAreas];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark Properties

- (void)setAllowedModifierFlags:(NSEventModifierFlags)newAllowedModifierFlags
          requiredModifierFlags:(NSEventModifierFlags)newRequiredModifierFlags
       allowsEmptyModifierFlags:(BOOL)newAllowsEmptyModifierFlags
{
    newAllowedModifierFlags &= SRCocoaModifierFlagsMask;
    newRequiredModifierFlags &= SRCocoaModifierFlagsMask;

    if ((newAllowedModifierFlags & newRequiredModifierFlags) != newRequiredModifierFlags)
    {
        [NSException raise:NSInvalidArgumentException
                    format:@"Required flags (%lu) MUST be allowed (%lu)", newAllowedModifierFlags, newRequiredModifierFlags];
    }

    if (newAllowsEmptyModifierFlags && newRequiredModifierFlags != 0)
    {
        [NSException raise:NSInvalidArgumentException
                    format:@"Empty modifier flags MUST be disallowed if required modifier flags are not empty."];
    }

    _allowedModifierFlags = newAllowedModifierFlags;
    _requiredModifierFlags = newRequiredModifierFlags;
    _allowsEmptyModifierFlags = newAllowsEmptyModifierFlags;
}

- (void)setEnabled:(BOOL)newEnabled
{
    _enabled = newEnabled;
    [self setNeedsDisplay:YES];

    if (!_enabled)
        [self endRecording];

    // Focus ring is only drawn when view is enabled
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
        [self noteFocusRingMaskChanged];
}

- (void)setObjectValue:(NSDictionary *)newObjectValue
{
    // Cocoa KVO and KVC frequently uses NSNull as object substituation of nil.
    // SRRecorderControl expects either nil or valid object value, it's convenient
    // to handle NSNull here and convert it into nil.
    if ((NSNull *)newObjectValue == [NSNull null])
        newObjectValue = nil;

    _objectValue = [newObjectValue copy];
    [self propagateValue:_objectValue forBinding:NSValueBinding];

    if (!self.isRecording)
    {
        NSAccessibilityPostNotification(self, NSAccessibilityTitleChangedNotification);
        [self setNeedsDisplay:YES];
    }
}


#pragma mark Methods

- (BOOL)beginRecording
{
    if (!self.enabled)
        return NO;

    if (self.isRecording)
        return YES;

    [self setNeedsDisplay:YES];

    if ([self.delegate respondsToSelector:@selector(shortcutRecorderShouldBeginRecording:)])
    {
        if (![self.delegate shortcutRecorderShouldBeginRecording:self])
        {
            NSBeep();
            return NO;
        }
    }

    [self willChangeValueForKey:@"isRecording"];
    _isRecording = YES;
    [self didChangeValueForKey:@"isRecording"];

    [self updateTrackingAreas];
    self.toolTip = SRLoc(@"Type shortcut");
    NSAccessibilityPostNotification(self, NSAccessibilityTitleChangedNotification);
    return YES;
}

- (void)endRecording
{
    [self endRecordingWithObjectValue:self.objectValue];
}

- (void)clearAndEndRecording
{
    [self endRecordingWithObjectValue:nil];
}

- (void)endRecordingWithObjectValue:(NSDictionary *)anObjectValue
{
    if (!self.isRecording)
        return;

    [self willChangeValueForKey:@"isRecording"];
    _isRecording = NO;
    [self didChangeValueForKey:@"isRecording"];

    self.objectValue = anObjectValue;

    [self updateTrackingAreas];
    self.toolTip = SRLoc(@"Click to record shortcut");
    [self setNeedsDisplay:YES];
    NSAccessibilityPostNotification(self, NSAccessibilityTitleChangedNotification);

    if (self.window.firstResponder == self && !self.canBecomeKeyView)
        [self.window makeFirstResponder:nil];

    if ([self.delegate respondsToSelector:@selector(shortcutRecorderDidEndRecording:)])
        [self.delegate shortcutRecorderDidEndRecording:self];
}


#pragma mark -

- (NSBezierPath *)controlShape
{
    NSRect shapeBounds = self.bounds;
    shapeBounds.size.height = _SRControlDimensions->height - self.alignmentRectInsets.bottom - self.alignmentRectInsets.top;

    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_9)
    {
        shapeBounds = NSInsetRect(shapeBounds, 1.0, 1.0);
    }

    return [NSBezierPath bezierPathWithRoundedRect:shapeBounds
                                           xRadius:_SRControlDimensions->shapeXRadius
                                           yRadius:_SRControlDimensions->shapeYRadius];
}

- (NSRect)rectForLabel:(NSString *)aLabel withAttributes:(NSDictionary *)anAttributes
{
    NSSize labelSize = [aLabel sizeWithAttributes:anAttributes];
    NSRect enclosingRect = NSInsetRect(self.bounds, _SRControlDimensions->shapeXRadius, 0.0);
    labelSize.width = fmin(ceil(labelSize.width), NSWidth(enclosingRect));
    labelSize.height = ceil(labelSize.height);
    CGFloat fontBaselineOffsetFromTop = labelSize.height + [anAttributes[NSFontAttributeName] descender];
    CGFloat baselineOffsetFromTop = _SRControlDimensions->height - self.baselineOffsetFromBottom;
    NSRect labelRect = {
        .origin = NSMakePoint(NSMidX(enclosingRect) - labelSize.width / 2.0, baselineOffsetFromTop - fontBaselineOffsetFromTop),
        .size = labelSize
    };
    labelRect = [self centerScanRect:labelRect];

    // Ensure label and buttons do not overlap.
    if (self.isRecording)
    {
        CGFloat rightOffsetFromButtons = NSMinX(self.snapBackButtonRect) - NSMaxX(labelRect);

        if (rightOffsetFromButtons < 0.0)
        {
            labelRect = NSOffsetRect(labelRect, rightOffsetFromButtons, 0.0);

            if (NSMinX(labelRect) < NSMinX(enclosingRect))
            {
                labelRect.size.width -= NSMinX(enclosingRect) - NSMinX(labelRect);
                labelRect.origin.x = NSMinX(enclosingRect);
            }
        }
    }

#ifdef DEBUG
    if (labelRect.size.width < labelSize.width || labelRect.size.height < labelSize.height)
        NSLog(@"WARNING: label rect (%@) is smaller than label size (%@). You may want to adjust size of the control.", NSStringFromRect(labelRect), NSStringFromSize(labelSize));
#endif

    return labelRect;
}

- (NSRect)snapBackButtonRect
{
    NSRect clearButtonRect = self.clearButtonRect;
    NSRect bounds = self.bounds;
    NSRect snapBackButtonRect = NSZeroRect;
    
    snapBackButtonRect.origin.x = NSMinX(clearButtonRect) - _SRControlDimensions->snapBackButton.rightOffset - _SRControlDimensions->snapBackButton.size.width - _SRControlDimensions->snapBackButton.leftOffset;
    snapBackButtonRect.origin.y = NSMinY(bounds);
    snapBackButtonRect.size.width = fdim(NSMinX(clearButtonRect), NSMinX(snapBackButtonRect));
    snapBackButtonRect.size.height = _SRControlDimensions->height;
    return snapBackButtonRect;
}

- (NSRect)clearButtonRect
{
    NSRect bounds = self.bounds;

    if ((self.objectValue).count)
    {
        NSRect clearButtonRect = NSZeroRect;
        clearButtonRect.origin.x = NSMaxX(bounds) - _SRControlDimensions->clearButton.rightOffset - _SRControlDimensions->clearButton.size.width - _SRControlDimensions->clearButton.leftOffset;
        clearButtonRect.origin.y = NSMinY(bounds);
        clearButtonRect.size.width = fdim(NSMaxX(bounds), NSMinX(clearButtonRect));
        clearButtonRect.size.height = _SRControlDimensions->height;
        return clearButtonRect;
    }
    else
    {
        return NSMakeRect(NSMaxX(bounds) - _SRControlDimensions->clearButton.rightOffset - _SRControlDimensions->clearButton.leftOffset,
                          NSMinY(bounds),
                          0.0,
                          _SRControlDimensions->height);
    }
}


#pragma mark -

- (NSString *)label
{
    NSString *label = nil;

    if (self.isRecording)
    {
        NSEventModifierFlags modifierFlags = [NSEvent modifierFlags] & self.allowedModifierFlags;

        if (modifierFlags)
            label = [[SRModifierFlagsTransformer sharedTransformer] transformedValue:@(modifierFlags)];
        else
            label = self.stringValue;

        if (!label.length)
            label = SRLoc(@"Type shortcut");
    }
    else
    {
        label = self.stringValue;

        if (!label.length)
            label = SRLoc(@"Click to record shortcut");
    }

    return label;
}

- (NSString *)accessibilityLabel
{
    NSString *label = nil;

    if (self.isRecording)
    {
        NSEventModifierFlags modifierFlags = [NSEvent modifierFlags] & self.allowedModifierFlags;
        label = [[SRModifierFlagsTransformer sharedPlainTransformer] transformedValue:@(modifierFlags)];

        if (!label.length)
            label = SRLoc(@"Type shortcut");
    }
    else
    {
        label = self.accessibilityStringValue;

        if (!label.length)
            label = SRLoc(@"Click to record shortcut");
    }

    return label;
}

- (NSString *)stringValue
{
    if (!(self.objectValue).count)
        return nil;

    NSString *f = [[SRModifierFlagsTransformer sharedTransformer] transformedValue:self.objectValue[SRShortcutModifierFlagsKey]];
    SRKeyCodeTransformer *transformer = nil;

    if (self.drawsASCIIEquivalentOfShortcut)
        transformer = [SRKeyCodeTransformer sharedPlainASCIITransformer];
    else
        transformer = [SRKeyCodeTransformer sharedPlainTransformer];

    NSString *c = [transformer transformedValue:self.objectValue[SRShortcutKeyCode]
                      withImplicitModifierFlags:nil
                          explicitModifierFlags:self.objectValue[SRShortcutModifierFlagsKey]];

    return [NSString stringWithFormat:@"%@%@", f, c];
}

- (NSString *)accessibilityStringValue
{
    if (!(self.objectValue).count)
        return nil;

    NSString *f = [[SRModifierFlagsTransformer sharedPlainTransformer] transformedValue:self.objectValue[SRShortcutModifierFlagsKey]];
    NSString *c = nil;

    if (self.drawsASCIIEquivalentOfShortcut)
        c = [[SRKeyCodeTransformer sharedPlainASCIITransformer] transformedValue:self.objectValue[SRShortcutKeyCode]];
    else
        c = [[SRKeyCodeTransformer sharedPlainTransformer] transformedValue:self.objectValue[SRShortcutKeyCode]];

    if (f.length > 0)
        return [NSString stringWithFormat:@"%@-%@", f, c];
    else
        return [NSString stringWithFormat:@"%@", c];
}

- (NSDictionary *)labelAttributes
{
    if (self.enabled)
    {
        if (self.isRecording)
            return [self recordingLabelAttributes];
        else
            return [self normalLabelAttributes];
    }
    else
        return [self disabledLabelAttributes];
}

- (NSDictionary *)normalLabelAttributes
{
    static dispatch_once_t OnceToken;
    static NSDictionary *NormalAttributes = nil;
    dispatch_once(&OnceToken, ^{
        NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
        p.alignment = NSCenterTextAlignment;
        p.lineBreakMode = NSLineBreakByTruncatingTail;
        p.baseWritingDirection = NSWritingDirectionLeftToRight;
        NormalAttributes = @{
            NSParagraphStyleAttributeName: [p copy],
            NSFontAttributeName: [NSFont labelFontOfSize:[NSFont smallSystemFontSize]],
            NSForegroundColorAttributeName: [NSColor controlTextColor]
        };
    });
    return NormalAttributes;
}

- (NSDictionary *)recordingLabelAttributes
{
    static dispatch_once_t OnceToken;
    static NSDictionary *RecordingAttributes = nil;
    dispatch_once(&OnceToken, ^{
        NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
        p.alignment = NSCenterTextAlignment;
        p.lineBreakMode = NSLineBreakByTruncatingTail;
        p.baseWritingDirection = NSWritingDirectionLeftToRight;
        RecordingAttributes = @{
            NSParagraphStyleAttributeName: [p copy],
            NSFontAttributeName: [NSFont labelFontOfSize:[NSFont systemFontSize]],
            NSForegroundColorAttributeName: [NSColor disabledControlTextColor]
        };
    });
    return RecordingAttributes;
}

- (NSDictionary *)disabledLabelAttributes
{
    static dispatch_once_t OnceToken;
    static NSDictionary *DisabledAttributes = nil;
    dispatch_once(&OnceToken, ^{
        NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
        p.alignment = NSCenterTextAlignment;
        p.lineBreakMode = NSLineBreakByTruncatingTail;
        p.baseWritingDirection = NSWritingDirectionLeftToRight;
        DisabledAttributes = @{
            NSParagraphStyleAttributeName: [p copy],
            NSFontAttributeName: [NSFont labelFontOfSize:[NSFont systemFontSize]],
            NSForegroundColorAttributeName: [NSColor disabledControlTextColor]
        };
    });
    return DisabledAttributes;
}


#pragma mark -

- (void)drawImage:(SRRecorderBezelImages *)images inRect:(NSRect)rect {
    NSDrawThreePartImage(rect,
                         images->left,
                         images->middle,
                         images->right,
                         NO,
                         NSCompositeSourceOver,
                         1.0,
                         self.isFlipped);
}

- (void)drawBackground:(NSRect)aDirtyRect
{
    NSRect frame = self.bounds;
    frame.size.height = _SRControlDimensions->height;

    if (![self needsToDrawRect:frame])
        return;

    [NSGraphicsContext saveGraphicsState];

    if (self.isRecording)
    {
        [self drawImage:&_SRImages.bezel.editing inRect:frame];
    }
    else
    {
        if (self.isMainButtonHighlighted)
        {
            if ([NSColor currentControlTint] == NSBlueControlTint)
            {
                [self drawImage:&_SRImages.bezel.highlighted.blue inRect:frame];
            }
            else
            {
                [self drawImage:&_SRImages.bezel.highlighted.graphite inRect:frame];
            }
        }
        else if (self.enabled)
        {
            [self drawImage:&_SRImages.bezel.normal inRect:frame];
        }
        else
        {
            [self drawImage:&_SRImages.bezel.disabled inRect:frame];
        }
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawInterior:(NSRect)aDirtyRect
{
    [self drawLabel:aDirtyRect];

    if (self.isRecording)
    {
        [self drawSnapBackButton:aDirtyRect];
        [self drawClearButton:aDirtyRect];
    }
}

- (void)drawLabel:(NSRect)aDirtyRect
{
    NSString *label = self.label;
    NSDictionary *labelAttributes = self.labelAttributes;
    NSRect labelRect = [self rectForLabel:label withAttributes:labelAttributes];

    if (![self needsToDrawRect:labelRect])
        return;

    [NSGraphicsContext saveGraphicsState];
    [label drawInRect:labelRect withAttributes:labelAttributes];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawSnapBackButton:(NSRect)aDirtyRect
{
    NSRect imageRect = self.snapBackButtonRect;
    
    imageRect.origin.x += _SRControlDimensions->snapBackButton.leftOffset;
    imageRect.origin.y += floor(self.alignmentRectInsets.top + (NSHeight(imageRect) - _SRControlDimensions->snapBackButton.size.height) / 2.0);
    imageRect.size = _SRControlDimensions->snapBackButton.size;
    imageRect = [self centerScanRect:imageRect];

    if (![self needsToDrawRect:imageRect])
        return;

    [NSGraphicsContext saveGraphicsState];

    if (self.isSnapBackButtonHighlighted)
    {
        [_SRImages.snapback.highlighted drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
    }
    else
    {
        [_SRImages.snapback.normal drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawClearButton:(NSRect)aDirtyRect
{
    NSRect imageRect = self.clearButtonRect;

    // If there is no reason to draw clear button (e.g. no shortcut was set)
    // rect will have empty width.
    if (NSWidth(imageRect) == 0.0)
        return;

    imageRect.origin.x += _SRControlDimensions->clearButton.leftOffset;
    imageRect.origin.y += floor(self.alignmentRectInsets.top + (NSHeight(imageRect) - _SRControlDimensions->clearButton.size.height) / 2.0);
    imageRect.size = _SRControlDimensions->clearButton.size;
    imageRect = [self centerScanRect:imageRect];

    if (![self needsToDrawRect:imageRect])
        return;

    [NSGraphicsContext saveGraphicsState];

    if (self.isClearButtonHighlighted)
    {
        [_SRImages.clear.highlighted drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
    }
    else
    {
        [_SRImages.clear.normal drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (CGFloat)backingScaleFactor
{
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6 || self.window == nil)
        return 1.0;
    else
        return self.window.backingScaleFactor;
}


#pragma mark -

- (BOOL)isMainButtonHighlighted
{
    if (_mouseTrackingButtonTag == _SRRecorderControlMainButtonTag)
    {
        NSPoint locationInView = [self convertPoint:self.window.mouseLocationOutsideOfEventStream
                                           fromView:nil];
        return [self mouse:locationInView inRect:self.bounds];
    }
    else
        return NO;
}

- (BOOL)isSnapBackButtonHighlighted
{
    if (_mouseTrackingButtonTag == _SRRecorderControlSnapBackButtonTag)
    {
        NSPoint locationInView = [self convertPoint:self.window.mouseLocationOutsideOfEventStream
                                           fromView:nil];
        return [self mouse:locationInView inRect:self.snapBackButtonRect];
    }
    else
        return NO;
}

- (BOOL)isClearButtonHighlighted
{
    if (_mouseTrackingButtonTag == _SRRecorderControlClearButtonTag)
    {
        NSPoint locationInView = [self convertPoint:self.window.mouseLocationOutsideOfEventStream
                                           fromView:nil];
        return [self mouse:locationInView inRect:self.clearButtonRect];
    }
    else
        return NO;
}

- (BOOL)areModifierFlagsValid:(NSEventModifierFlags)aModifierFlags forKeyCode:(unsigned short)aKeyCode
{
    aModifierFlags &= SRCocoaModifierFlagsMask;

    if ([self.delegate respondsToSelector:@selector(shortcutRecorder:shouldUnconditionallyAllowModifierFlags:forKeyCode:)] &&
        [self.delegate shortcutRecorder:self shouldUnconditionallyAllowModifierFlags:aModifierFlags forKeyCode:aKeyCode])
    {
        return YES;
    }
    else if (aModifierFlags == 0 && !self.allowsEmptyModifierFlags)
        return NO;
    else if ((aModifierFlags & self.requiredModifierFlags) != self.requiredModifierFlags)
        return NO;
    else if ((aModifierFlags & self.allowedModifierFlags) != aModifierFlags)
        return NO;
    else
        return YES;
}


#pragma mark -

- (void)propagateValue:(id)aValue forBinding:(NSString *)aBinding
{
    NSParameterAssert(aBinding != nil);

    NSDictionary* bindingInfo = [self infoForBinding:aBinding];

    if(!bindingInfo || (id)bindingInfo == [NSNull null])
        return;

    NSObject *boundObject = bindingInfo[NSObservedObjectKey];

    if(!boundObject || (id)boundObject == [NSNull null])
        [NSException raise:NSInternalInconsistencyException format:@"NSObservedObjectKey MUST NOT be nil for binding \"%@\"", aBinding];

    NSString* boundKeyPath = bindingInfo[NSObservedKeyPathKey];

    if(!boundKeyPath || (id)boundKeyPath == [NSNull null])
        [NSException raise:NSInternalInconsistencyException format:@"NSObservedKeyPathKey MUST NOT be nil for binding \"%@\"", aBinding];

    NSDictionary* bindingOptions = bindingInfo[NSOptionsKey];

    if(bindingOptions)
    {
        NSValueTransformer* transformer = [bindingOptions valueForKey:NSValueTransformerBindingOption];

        if(!transformer || (id)transformer == [NSNull null])
        {
            NSString* transformerName = [bindingOptions valueForKey:NSValueTransformerNameBindingOption];

            if(transformerName && (id)transformerName != [NSNull null])
                transformer = [NSValueTransformer valueTransformerForName:transformerName];
        }

        if(transformer && (id)transformer != [NSNull null])
        {
            if([[transformer class] allowsReverseTransformation])
                aValue = [transformer reverseTransformedValue:aValue];
#ifdef DEBUG
            else
                NSLog(@"WARNING: binding \"%@\" has value transformer, but it doesn't allow reverse transformations in %s", aBinding, __PRETTY_FUNCTION__);
#endif
        }
    }

    [boundObject setValue:aValue forKeyPath:boundKeyPath];
}

+ (BOOL)automaticallyNotifiesObserversOfValue
{
    return NO;
}

- (void)setValue:(id)newValue
{
    if (NSIsControllerMarker(newValue))
        [NSException raise:NSInternalInconsistencyException format:@"SRRecorderControl's NSValueBinding does not support controller value markers."];

    self.objectValue = newValue;
}

- (id)value
{
    return self.objectValue;
}


#pragma mark NSAccessibility

- (BOOL)accessibilityIsIgnored
{
    return NO;
}

- (NSArray *)accessibilityAttributeNames
{
    static NSArray *AttributeNames = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^
    {
        AttributeNames = [[super accessibilityAttributeNames] mutableCopy];
        NSArray *newAttributes = @[
            NSAccessibilityRoleAttribute,
            NSAccessibilityTitleAttribute,
            NSAccessibilityEnabledAttribute
        ];

        for (NSString *attributeName in newAttributes)
        {
            if (![AttributeNames containsObject:attributeName])
                [(NSMutableArray *)AttributeNames addObject:attributeName];
        }

        AttributeNames = [AttributeNames copy];
    });
    return AttributeNames;
}

- (id)accessibilityAttributeValue:(NSString *)anAttributeName
{
    if ([anAttributeName isEqualToString:NSAccessibilityRoleAttribute])
        return NSAccessibilityButtonRole;
    else if ([anAttributeName isEqualToString:NSAccessibilityTitleAttribute])
        return self.accessibilityLabel;
    else if ([anAttributeName isEqualToString:NSAccessibilityEnabledAttribute])
        return @(self.enabled);
    else
        return [super accessibilityAttributeValue:anAttributeName];
}

- (NSArray *)accessibilityActionNames
{
    static NSArray *AllActions = nil;
    static NSArray *ButtonStateActionNames = nil;
    static NSArray *RecorderStateActionNames = nil;

    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^
    {
        AllActions = @[
            NSAccessibilityPressAction,
            NSAccessibilityCancelAction,
            NSAccessibilityDeleteAction
        ];

        ButtonStateActionNames = @[
            NSAccessibilityPressAction
        ];

        RecorderStateActionNames = @[
            NSAccessibilityCancelAction,
            NSAccessibilityDeleteAction
        ];
    });

    // List of supported actions names must be fixed for 10.6, but can vary for 10.7 and above.
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
    {
        if (self.enabled)
        {
            if (self.isRecording)
                return RecorderStateActionNames;
            else
                return ButtonStateActionNames;
        }
        else
            return @[];
    }
    else
        return AllActions;
}

- (NSString *)accessibilityActionDescription:(NSString *)anAction
{
    return NSAccessibilityActionDescription(anAction);
}

- (void)accessibilityPerformAction:(NSString *)anAction
{
    if ([anAction isEqualToString:NSAccessibilityPressAction])
        [self beginRecording];
    else if (self.isRecording && [anAction isEqualToString:NSAccessibilityCancelAction])
        [self endRecording];
    else if (self.isRecording && [anAction isEqualToString:NSAccessibilityDeleteAction])
        [self clearAndEndRecording];
}


#pragma mark NSToolTipOwner

- (NSString *)view:(NSView *)aView stringForToolTip:(NSToolTipTag)aTag point:(NSPoint)aPoint userData:(void *)aData
{
    if (aTag == _snapBackButtonToolTipTag)
        return SRLoc(@"Use old shortcut");
    else
        return [super view:aView stringForToolTip:aTag point:aPoint userData:aData];
}


#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
    // Since Xcode 6.x, user can configure xib to Prefer Coder.
    // In that case view will be instantiated with initWithCoder.
    //
    // awakeFromNib cannot be used to set up defaults for IBDesignable,
    // because at the time it's called, it's impossible to know whether properties
    // were set by a user in xib or they are compilation-time defaults.
    self = [super initWithCoder:aCoder];

    if (self)
    {
        [self _initInternalState];
    }

    return self;
}


#pragma mark NSView

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)viewWillDraw
{
    [super viewWillDraw];
    
    // cannot use appearance in asset catalog because we are targetting < 10.14 so it's not supported
    NSAppearanceName currentAppearance;
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_13) {
        currentAppearance = @"";
    } else {
        if (@available(macOS 10.14, *)) {
            currentAppearance = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        }
    }
    
    if(![_SRLoadedAppearanceName isEqualToString:currentAppearance]) {
        _SRLoadedAppearanceName = currentAppearance;
        NSString *appearanceText = currentAppearance.length ? [[currentAppearance stringByReplacingOccurrencesOfString:@"NSAppearanceName" withString:@""] stringByAppendingString:@"-"] : currentAppearance;
        void(^setImage)(NSImage * __strong *, NSString *) = ^(NSImage * __strong * structPointer, NSString * imageName) {
            *structPointer = SRImage([NSString stringWithFormat:@"%@%@%@", _SRImageNamePrefix, appearanceText, imageName]);
        };
        void(^setBezelImage)(SRRecorderBezelImages *, NSString *) = ^(SRRecorderBezelImages *bezelImages, NSString * prefix) {
            setImage(&bezelImages->left, [prefix stringByAppendingString:@"-left"]);
            setImage(&bezelImages->middle, [prefix stringByAppendingString:@"-middle"]);
            setImage(&bezelImages->right, [prefix stringByAppendingString:@"-right"]);
        };
        setBezelImage(&_SRImages.bezel.highlighted.blue, @"bezel-blue-highlighted");
        setBezelImage(&_SRImages.bezel.highlighted.graphite, @"bezel-graphite-highlighted");
        setBezelImage(&_SRImages.bezel.normal, @"bezel");
        setBezelImage(&_SRImages.bezel.editing, @"bezel-editing");
        setBezelImage(&_SRImages.bezel.disabled, @"bezel-disabled");
        setImage(&_SRImages.clear.normal, @"clear");
        setImage(&_SRImages.clear.highlighted, @"clear-highlighted");
        setImage(&_SRImages.snapback.normal, @"snapback");
        setImage(&_SRImages.snapback.highlighted, @"snapback-highlighted");
    }
}

- (void)drawRect:(NSRect)aDirtyRect
{
    [self drawBackground:aDirtyRect];
    [self drawInterior:aDirtyRect];

    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6)
    {
        if (self.enabled && self.window.firstResponder == self)
        {
            [NSGraphicsContext saveGraphicsState];
            NSSetFocusRingStyle(NSFocusRingOnly);
            [self.controlShape fill];
            [NSGraphicsContext restoreGraphicsState];
        }
    }
}

- (void)drawFocusRingMask
{
    if (self.enabled && self.window.firstResponder == self)
        [self.controlShape fill];
}

- (NSRect)focusRingMaskBounds
{
    if (self.enabled && self.window.firstResponder == self)
        return self.controlShape.bounds;
    else
        return NSZeroRect;
}

- (NSEdgeInsets)alignmentRectInsets
{
    return NSEdgeInsetsMake(0.0, 0.0, _SRControlDimensions->bottomShadowHeight, 0.0);
}

- (CGFloat)baselineOffsetFromBottom
{
    // True method to calculate is presented below. Unfortunately Cocoa implementation of Mac OS X 10.8.2 expects this value to be persistant.
    // If baselineOffsetFromBottom depends on some other properties and may return different values for different calls,
    // NSLayoutFormatAlignAllBaseline may not work. For this reason we return the constant.
    // If you're going to change layout of the view, uncomment the line below, look what it typically returns and update the constant.
    // TODO: Hopefully it will be fixed some day in Cocoa and therefore in SRRecorderControl.
//    CGFloat baseline = fdim(NSHeight(self.bounds), _SRControlDimensions->height) + floor(_SRRecorderControlBaselineOffset - [self.labelAttributes[NSFontAttributeName] descender]);
    return 8.0;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(NSWidth([self rectForLabel:SRLoc(@"Click to record shortcut") withAttributes:self.labelAttributes]) + _SRControlDimensions->shapeXRadius + _SRControlDimensions->shapeXRadius,
                      _SRControlDimensions->height);
}

- (void)updateTrackingAreas
{
    static const NSTrackingAreaOptions TrackingOptions = NSTrackingMouseEnteredAndExited | NSTrackingActiveWhenFirstResponder | NSTrackingEnabledDuringMouseDrag;

    if (_mainButtonTrackingArea)
        [self removeTrackingArea:_mainButtonTrackingArea];

    _mainButtonTrackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:TrackingOptions
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:_mainButtonTrackingArea];

    if (_snapBackButtonTrackingArea)
    {
        [self removeTrackingArea:_snapBackButtonTrackingArea];
        _snapBackButtonTrackingArea = nil;
    }

    if (_clearButtonTrackingArea)
    {
        [self removeTrackingArea:_clearButtonTrackingArea];
        _clearButtonTrackingArea = nil;
    }

    if (_snapBackButtonToolTipTag != NSIntegerMax)
    {
        [self removeToolTip:_snapBackButtonToolTipTag];
        _snapBackButtonToolTipTag = NSIntegerMax;
    }

    if (self.isRecording)
    {
        _snapBackButtonTrackingArea = [[NSTrackingArea alloc] initWithRect:self.snapBackButtonRect
                                                                   options:TrackingOptions
                                                                     owner:self
                                                                  userInfo:nil];
        [self addTrackingArea:_snapBackButtonTrackingArea];
        _clearButtonTrackingArea = [[NSTrackingArea alloc] initWithRect:self.clearButtonRect
                                                                options:TrackingOptions
                                                                  owner:self
                                                               userInfo:nil];
        [self addTrackingArea:_clearButtonTrackingArea];

        // Since this method is used to set up tracking rects of aux buttons, the rest of the code is aware
        // it should be called whenever geometry or apperance changes. Therefore it's a good place to set up tooltip rects.
        _snapBackButtonToolTipTag = [self addToolTipRect:_snapBackButtonTrackingArea.rect owner:self userData:NULL];
    }
}

- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
    // We want control to end recording whenever window resigns first responder status.
    // Otherwise we could end up with "dangling" recording.
    if (self.window)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSWindowDidResignKeyNotification
                                                      object:self.window];
    }

    if (aWindow)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(endRecording)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:aWindow];
    }

    [super viewWillMoveToWindow:aWindow];
}


#pragma mark NSResponder

- (BOOL)acceptsFirstResponder
{
    return self.enabled;
}

- (BOOL)becomeFirstResponder
{
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6)
        [self setKeyboardFocusRingNeedsDisplayInRect:self.bounds];

    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6)
        [self setKeyboardFocusRingNeedsDisplayInRect:self.bounds];

    [self endRecording];
    _mouseTrackingButtonTag = _SRRecorderControlInvalidButtonTag;
    return [super resignFirstResponder];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)anEvent
{
    return YES;
}

- (BOOL)canBecomeKeyView
{
    // SRRecorderControl uses the button metaphor, but buttons cannot become key unless
    // Full Keyboard Access is enabled. Respect this.
    return super.canBecomeKeyView && NSApp.fullKeyboardAccessEnabled;
}

- (BOOL)needsPanelToBecomeKey
{
    return YES;
}

- (void)mouseDown:(NSEvent *)anEvent
{
    if (!self.enabled)
    {
        [super mouseDown:anEvent];
        return;
    }

    NSPoint locationInView = [self convertPoint:anEvent.locationInWindow fromView:nil];

    if (self.isRecording)
    {
        if ([self mouse:locationInView inRect:self.snapBackButtonRect])
        {
            _mouseTrackingButtonTag = _SRRecorderControlSnapBackButtonTag;
            [self setNeedsDisplayInRect:self.snapBackButtonRect];
        }
        else if ([self mouse:locationInView inRect:self.clearButtonRect])
        {
            _mouseTrackingButtonTag = _SRRecorderControlClearButtonTag;
            [self setNeedsDisplayInRect:self.clearButtonRect];
        }
        else
            [super mouseDown:anEvent];
    }
    else if ([self mouse:locationInView inRect:self.bounds])
    {
        _mouseTrackingButtonTag = _SRRecorderControlMainButtonTag;
        [self setNeedsDisplay:YES];
    }
    else
        [super mouseDown:anEvent];
}

- (void)mouseUp:(NSEvent *)anEvent
{
    if (!self.enabled)
    {
        [super mouseUp:anEvent];
        return;
    }

    if (_mouseTrackingButtonTag != _SRRecorderControlInvalidButtonTag)
    {
        if (!self.window.isKeyWindow)
        {
            // It's possible to receive this event after window resigned its key status
            // e.g. when shortcut brings new window and makes it key.
            [self setNeedsDisplay:YES];
        }
        else
        {
            NSPoint locationInView = [self convertPoint:anEvent.locationInWindow fromView:nil];

            if (_mouseTrackingButtonTag == _SRRecorderControlMainButtonTag &&
                [self mouse:locationInView inRect:self.bounds])
            {
                [self beginRecording];
            }
            else if (_mouseTrackingButtonTag == _SRRecorderControlSnapBackButtonTag &&
                     [self mouse:locationInView inRect:self.snapBackButtonRect])
            {
                [self endRecording];
            }
            else if (_mouseTrackingButtonTag == _SRRecorderControlClearButtonTag &&
                     [self mouse:locationInView inRect:self.clearButtonRect])
            {
                [self clearAndEndRecording];
            }
        }

        _mouseTrackingButtonTag = _SRRecorderControlInvalidButtonTag;
    }
    else
        [super mouseUp:anEvent];
}

- (void)mouseEntered:(NSEvent *)anEvent
{
    if (!self.enabled)
    {
        [super mouseEntered:anEvent];
        return;
    }

    if ((_mouseTrackingButtonTag == _SRRecorderControlMainButtonTag && anEvent.trackingArea == _mainButtonTrackingArea) ||
        (_mouseTrackingButtonTag == _SRRecorderControlSnapBackButtonTag && anEvent.trackingArea == _snapBackButtonTrackingArea) ||
        (_mouseTrackingButtonTag == _SRRecorderControlClearButtonTag && anEvent.trackingArea == _clearButtonTrackingArea))
    {
        [self setNeedsDisplayInRect:anEvent.trackingArea.rect];
    }

    [super mouseEntered:anEvent];
}

- (void)mouseExited:(NSEvent *)anEvent
{
    if (!self.enabled)
    {
        [super mouseExited:anEvent];
        return;
    }

    if ((_mouseTrackingButtonTag == _SRRecorderControlMainButtonTag && anEvent.trackingArea == _mainButtonTrackingArea) ||
        (_mouseTrackingButtonTag == _SRRecorderControlSnapBackButtonTag && anEvent.trackingArea == _snapBackButtonTrackingArea) ||
        (_mouseTrackingButtonTag == _SRRecorderControlClearButtonTag && anEvent.trackingArea == _clearButtonTrackingArea))
    {
        [self setNeedsDisplayInRect:anEvent.trackingArea.rect];
    }

    [super mouseExited:anEvent];
}

- (void)keyDown:(NSEvent *)anEvent
{
    if (![self performKeyEquivalent:anEvent])
        [super keyDown:anEvent];
}

- (BOOL)performKeyEquivalent:(NSEvent *)anEvent
{
    if (!self.enabled)
        return NO;

    if (self.window.firstResponder != self)
        return NO;

    if (_mouseTrackingButtonTag != _SRRecorderControlInvalidButtonTag)
        return NO;

    if (self.isRecording)
    {
        if (anEvent.keyCode == USHRT_MAX)
        {
            // This shouldn't really happen ever, but was rarely observed.
            // See https://github.com/Kentzo/ShortcutRecorder/issues/40
            return NO;
        }
        else if (self.allowsEscapeToCancelRecording &&
            anEvent.keyCode == kVK_Escape &&
            (anEvent.modifierFlags & SRCocoaModifierFlagsMask) == 0)
        {
            [self endRecording];
            return YES;
        }
        else if (self.allowsDeleteToClearShortcutAndEndRecording &&
                (anEvent.keyCode == kVK_Delete || anEvent.keyCode == kVK_ForwardDelete) &&
                (anEvent.modifierFlags & SRCocoaModifierFlagsMask) == 0)
        {
            [self clearAndEndRecording];
            return YES;
        }
        else if ([self areModifierFlagsValid:anEvent.modifierFlags forKeyCode:anEvent.keyCode])
        {
            NSDictionary *newObjectValue = @{
                SRShortcutKeyCode: @(anEvent.keyCode),
                SRShortcutModifierFlagsKey: @(anEvent.modifierFlags & SRCocoaModifierFlagsMask),
                SRShortcutCharacters: anEvent.characters,
                SRShortcutCharactersIgnoringModifiers: anEvent.charactersIgnoringModifiers
            };

            if ([self.delegate respondsToSelector:@selector(shortcutRecorder:canRecordShortcut:)])
            {
                if (![self.delegate shortcutRecorder:self canRecordShortcut:newObjectValue])
                {
                    // We acutally handled key equivalent, because client likely performs some action
                    // to represent an error (e.g. beep and error dialog).
                    // Do not end editing, because if client do not use additional window to show an error
                    // first responder will not change. Allow a user to make another attempt.
                    return YES;
                }
            }

            [self endRecordingWithObjectValue:newObjectValue];
            return YES;
        }
    }
    else if (anEvent.keyCode == kVK_Space)
        return [self beginRecording];

    return NO;
}

- (void)flagsChanged:(NSEvent *)anEvent
{
    if (self.isRecording)
    {
        NSEventModifierFlags modifierFlags = anEvent.modifierFlags & SRCocoaModifierFlagsMask;
        if (modifierFlags != 0 && ![self areModifierFlagsValid:modifierFlags forKeyCode:anEvent.keyCode])
            NSBeep();

        [self setNeedsDisplay:YES];
    }

    [super flagsChanged:anEvent];
}

@end
