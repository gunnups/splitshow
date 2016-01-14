//
//  CustomLayoutController.m
//  SplitShow
//
//  Created by Moritz Pflanzer on 27/12/2015.
//  Copyright © 2015 Moritz Pflanzer. All rights reserved.
//

#import "CustomLayoutController.h"
#import "AppDelegate.h"
#import <Quartz/Quartz.h>
#import "SplitShowDocument.h"
#import "Utilities.h"
#import "DestinationLayoutView.h"
#import "PreviewController.h"
#import "NSScreen+Name.h"

@interface CustomLayoutController ()

@property (readwrite) NSMutableArray<NSMutableArray<NSNumber*>*> *screenLayouts;
@property (readonly) SplitShowDocument *splitShowDocument;
@property (readwrite) NSMutableArray *previewImages;
@property IBOutlet NSArrayController *previewImageController;
@property IBOutlet NSCollectionView *sourceView;
@property IBOutlet DestinationLayoutView *destinationView;

- (void)setupScreenLayouts;
- (void)generatePreviewImages;
- (void)documentActivateNotification:(NSNotification *)notification;
- (void)documentDeactivateNotification:(NSNotification *)notification;

- (IBAction)changeLayoutMode:(NSPopUpButton*)button;

@end

@implementation CustomLayoutController

+ (instancetype)sharedCustomLayoutController
{
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[super alloc] initWithWindowNibName:@"CustomLayout"];
    });

    return sharedInstance;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    self.window.restorationClass = [[[NSApplication sharedApplication] delegate] class];

    self.previewImages = [NSMutableArray array];

    self.document = [[NSDocumentController sharedDocumentController] currentDocument];

    if(!self.splitShowDocument.customLayoutMode)
    {
        self.splitShowDocument.customLayoutMode = kSplitShowSlideModeNormal;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentActivateNotification:) name:kSplitShowNotificationWindowDidBecomeMain object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentDeactivateNotification:) name:kSplitShowNotificationWindowDidResignMain object:nil];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupScreenLayouts
{
    self.screenLayouts = [NSMutableArray array];

    for(NSInteger screenIndex = 0; screenIndex < [[NSScreen screens] count]; ++screenIndex)
    {
        if(screenIndex < self.splitShowDocument.customLayouts.count)
        {
            NSMutableArray *tmp = [NSMutableArray arrayWithArray:[self.splitShowDocument.customLayouts objectAtIndex:screenIndex]];
            [self.screenLayouts addObject:tmp];
        }
        else
        {
            [self.screenLayouts addObject:[NSMutableArray array]];
        }
    }
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    return [NSString stringWithFormat:@"%@ - %@", self.splitShowDocument.name, NSLocalizedString(@"Custom layout", @"Custom layout")];
}

- (SplitShowDocument *)splitShowDocument
{
    return (SplitShowDocument*)self.document;
}

- (void)documentActivateNotification:(NSNotification *)notification
{
    self.document = notification.object;
}

- (void)documentDeactivateNotification:(NSNotification *)notification
{
    self.document = nil;
}

- (void)setDocument:(id)document
{
    [super setDocument:document];

    if([kSplitShowSlideModeNormal isEqualToString:self.splitShowDocument.customLayoutMode])
    {
        self.pdfDocument = [self.splitShowDocument createMirroredDocument];
    }
    else if([kSplitShowSlideModeSplit isEqualToString:self.splitShowDocument.customLayoutMode])
    {
        self.pdfDocument = [self.splitShowDocument createSplitDocument];
    }
    else
    {
        self.pdfDocument = [self.splitShowDocument createMirroredDocument];
    }

    [self setupScreenLayouts];
    [self generatePreviewImages];
    self.destinationView.previewImages = self.previewImages;
    [self.destinationView loadLayouts];
}

- (IBAction)changeLayoutMode:(NSPopUpButton *)button
{
    switch(button.selectedTag)
    {
        case 0:
            self.splitShowDocument.customLayoutMode = kSplitShowSlideModeNormal;
            self.pdfDocument = [self.splitShowDocument createMirroredDocument];
            break;

        case 1:
            self.splitShowDocument.customLayoutMode = kSplitShowSlideModeSplit;
            self.pdfDocument = [self.splitShowDocument createSplitDocument];
            break;
    }

    [self removeAllSlides];
    [self generatePreviewImages];
    self.destinationView.previewImages = self.previewImages;
    [self.destinationView loadLayouts];
}

#pragma mark - CustomLayoutDelegate

- (NSInteger)numberOfScreens
{
    return self.screenLayouts.count;
}

- (NSInteger)maxSlidesPerScreen
{
    NSUInteger max = 0;

    for(NSArray *items in self.screenLayouts)
    {
        max = MAX(max, items.count);
    }

    return max;
}

- (NSInteger)numberOfSlidesForScreenAtIndex:(NSInteger)index
{
    return [[self.screenLayouts objectAtIndex:index] count];
}

- (NSString*)nameOfScreenAtIndex:(NSInteger)index
{
    return [[[NSScreen screens] objectAtIndex:index] name];
}

- (NSInteger)slideAtIndex:(NSInteger)slideIndex forScreen:(NSInteger)screenIndex
{
    return [[[self.screenLayouts objectAtIndex:screenIndex] objectAtIndex:slideIndex] integerValue];
}

- (void)insertSlide:(NSInteger)slide atIndex:(NSInteger)slideIndex forScreen:(NSInteger)screenIndex
{
    [[self.screenLayouts objectAtIndex:screenIndex] insertObject:@(slide) atIndex:slideIndex];
    self.splitShowDocument.customLayouts = self.screenLayouts;
}

- (void)replaceSlideAtIndex:(NSInteger)slideIndex withSlide:(NSInteger)slide forScreen:(NSInteger)screenIndex
{
    [[self.screenLayouts objectAtIndex:screenIndex] replaceObjectAtIndex:slideIndex withObject:@(slide)];
    self.splitShowDocument.customLayouts = self.screenLayouts;
}

- (void)removeSlideAtIndex:(NSInteger)slideIndex forScreen:(NSInteger)screenIndex
{
    [[self.screenLayouts objectAtIndex:screenIndex] removeObjectAtIndex:slideIndex];
    self.splitShowDocument.customLayouts = self.screenLayouts;
}

- (void)removeAllSlides
{
    for(NSMutableArray *slides in self.screenLayouts)
    {
        [slides removeAllObjects];
    }

    self.splitShowDocument.customLayouts = self.screenLayouts;
}

#pragma mark -

- (void)generatePreviewImages
{
    if(!self.previewImageController)
    {
        return;
    }
    
    [self.previewImageController removeObjects:self.previewImageController.arrangedObjects];

    for(NSUInteger i = 0; i < self.pdfDocument.pageCount; ++i)
    {
        PDFPage *page = [self.pdfDocument pageAtIndex:i];
        NSRect bounds = [page boundsForBox:kPDFDisplayBoxMediaBox];
        NSImage *image = [[NSImage alloc] initWithSize:bounds.size];

        [image lockFocus];
        [page drawWithBox:kPDFDisplayBoxMediaBox];
        [image unlockFocus];

        [self.previewImageController addObject:image];
    }
}

- (IBAction)selectItems:(NSPopUpButton*)button;
{
    switch(button.selectedTag)
    {
        case 1:
            // Select none
            [self.sourceView deselectAll:self];
            break;

        case 2:
        {
            // Select odd
            NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];

            for(NSUInteger i = 0; i < self.pdfDocument.pageCount; i += 2)
            {
                [indices addIndex:i];
            }

            self.sourceView.selectionIndexes = indices;
            break;
        }

        case 3:
        {
            // Select even
            NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];

            for(NSUInteger i = 1; i < self.pdfDocument.pageCount; i += 2)
            {
                [indices addIndex:i];
            }

            self.sourceView.selectionIndexes = indices;
            break;
        }

        case 4:
        {
            // Select all
            [self.sourceView selectAll:self];
            break;
        }
    }

    [button selectItemWithTag:0];
}

- (BOOL)collectionView:(NSCollectionView *)collectionView canDragItemsAtIndexes:(NSIndexSet *)indexes withEvent:(NSEvent *)event
{
    return YES;
}

- (BOOL)collectionView:(NSCollectionView *)collectionView writeItemsAtIndexes:(NSIndexSet *)indexes toPasteboard:(NSPasteboard *)pasteboard
{
    NSData *indexData = [NSKeyedArchiver archivedDataWithRootObject:indexes];
    [pasteboard declareTypes:@[kSplitShowLayoutData] owner:nil];
    [pasteboard setData:indexData forType:kSplitShowLayoutData];
    
    return YES;
}

@end