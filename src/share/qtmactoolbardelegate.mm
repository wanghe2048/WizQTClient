/****************************************************************************
 **
 ** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 ** All rights reserved.
 ** Contact: Nokia Corporation (qt-info@nokia.com)
 **
 ** This file is part of the examples of the Qt Toolkit.
 **
 ** You may use this file under the terms of the BSD license as follows:
 **
 ** "Redistribution and use in source and binary forms, with or without
 ** modification, are permitted provided that the following conditions are
 ** met:
 **   * Redistributions of source code must retain the above copyright
 **     notice, this list of conditions and the following disclaimer.
 **   * Redistributions in binary form must reproduce the above copyright
 **     notice, this list of conditions and the following disclaimer in
 **     the documentation and/or other materials provided with the
 **     distribution.
 **   * Neither the name of Nokia Corporation and its Subsidiary(-ies) nor
 **     the names of its contributors may be used to endorse or promote
 **     products derived from this software without specific prior written
 **     permission.
 **
 ** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 ** "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 ** LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 ** A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 ** OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 ** SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOTgall
 ** LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 ** DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 ** THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 ** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 ** OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 ** $QT_END_LICENSE$
 **
 ****************************************************************************/


#include "qtmactoolbardelegate.h"
#include "cocoahelp_mac.h"
#include <qdebug.h>
#include <QPixmap>

NSString *toNSStandardItem(MacToolButton::StandardItem standardItem);


NSMutableArray *itemIdentifiers(const QList<QObject *> *items, bool cullUnselectable)
{
    NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];

    foreach (const QObject * object, *items)
    {
        // Handle MacToolButtons
        const MacToolButton *item = qobject_cast<const MacToolButton *>(object);
        if (!item)
            continue;
        if (cullUnselectable && item->selectable() == false)
            continue;
        if (item->standardItem() == MacToolButton::NoItem) {
            [array addObject: toNSString(QString::number(qulonglong(item)))];
        } else {
            [array addObject: toNSStandardItem(item->standardItem())];
        }
    }
    return array;
}


@implementation QtMacToolbarDelegate

- (id)init
{
    toolbar = nil;
    //
    self = [super init];
    if (self) {
        items = new QList<QObject *>();
        allowedItems = new QList<QObject *>();
    }
    return self;
}

- (void)dealloc
{
    delete items;
    delete allowedItems;
    [super dealloc];
}


- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)tb
{
    Q_UNUSED(tb);
    return itemIdentifiers(self->items, false);
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)tb
{
    Q_UNUSED(tb);
    return itemIdentifiers(self->allowedItems, false);
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)tb
{
    Q_UNUSED(tb);
    NSMutableArray *array = itemIdentifiers(self->items, true);
    [array addObjectsFromArray: itemIdentifiers(self->allowedItems, true)];
    return array;
}



- (NSToolbarItemGroup* )findItemGroup:(NSToolbarItem*)item itemIndex:(int*)itemIndex
{
    if (toolbar == nil)
        return nil;
    //
    NSArray* arr = [toolbar items];
    int count = [arr count];
    for (int i = 0; i < count; i++)
    {
        NSObject* obj = [arr objectAtIndex:i];
        if ([obj isKindOfClass:[NSToolbarItemGroup class]])
        {
            NSToolbarItemGroup* groupItem = (NSToolbarItemGroup *)obj;
            //
            NSArray* groupSubItems = [groupItem subitems];
            int groupSubItemCount = [groupSubItems count];
            for (int j = 0; j < groupSubItemCount; j++)
            {
                NSObject* groupSubItemObject = [groupSubItems objectAtIndex:j];
                if ([groupSubItemObject isKindOfClass:[NSToolbarItem class]])
                {
                    NSToolbarItem* groupSubItem = (NSToolbarItem *)groupSubItemObject;
                    if (groupSubItem == item)
                    {
                        *itemIndex = j;
                        return groupItem;
                    }
                }
            }
        }
    }
    return nil;
}

- (IBAction)itemClicked:(id)sender
{
    NSToolbarItem *item = reinterpret_cast<NSToolbarItem *>(sender);
    //
    QString identifier = toQString([item itemIdentifier]);
    QObject *obj = reinterpret_cast<QObject *>(identifier.toULongLong());
    if (obj)
    {
        if (MacToolButton *toolButton = dynamic_cast<MacToolButton *>(obj))
        {
            if (toolButton->m_action) {
                toolButton->m_action->trigger();
            }
            //
            toolButton->emitActivated();
        }
        else if (QAction *action = dynamic_cast<QAction *>(obj))
        {
            action->trigger();
            //
            int itemIndex = -1;
            NSToolbarItemGroup* groupItem = [self findItemGroup:item itemIndex:&itemIndex];
            if (-1 != itemIndex && groupItem != nil)
            {
                NSView* view = [groupItem view];
                if ([view isKindOfClass:[NSSegmentedControl class]])
                {
                    NSSegmentedControl* control = (NSSegmentedControl *)view;
                    [control setSelected:NO forSegment:itemIndex];
                }
            }
        }
    }
    //
}

- (NSToolbarItem *) toolbar: (NSToolbar *)tb itemForItemIdentifier: (NSString *) itemIdentifier willBeInsertedIntoToolbar:(BOOL) willBeInserted
{
    toolbar = tb;
    //
    Q_UNUSED(willBeInserted);
    const QString identifier = toQString(itemIdentifier);

    //qDebug() << "toolbar for identifier" << identifier;
    //return 0;

    QObject *itemObject = reinterpret_cast<QObject *>(identifier.toULongLong()); // string -> unisgned long long -> pointer

    // Rest of function handles MacToolButtons.
    MacToolButton *toolButton = qobject_cast<MacToolButton *>(itemObject);
    if (!toolButton) {
        qDebug() << "Could not find toolbutton for itemIdentifier:" << identifier;
        return nil;
    }
    //
    if (toolButton->isGroup())
    {
        NSToolbarItemGroup *group = [[[NSToolbarItemGroup alloc] initWithItemIdentifier:itemIdentifier] autorelease];
        NSSegmentedControl* groupView = [[NSSegmentedControl alloc] init];
        [groupView setSegmentStyle:NSSegmentStyleTexturedRounded];

        NSMutableArray* groupItems = [NSMutableArray array];
        //
        QActionGroup* actionGroup = toolButton->actionGroup();
        QList<QAction*> actions = actionGroup->actions();

        int actionCount = actions.count();
        [groupView setSegmentCount:actionCount];
        //
        for (int i = 0; i < actionCount; i++)
        {
            QAction* action = actions.at(i);
            //
            QString actionIdentifier = QString::number(qulonglong(action));
            NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: toNSString(actionIdentifier)] autorelease];

            [toolbarItem setLabel: toNSString(action->text())];
            [toolbarItem setPaletteLabel:[toolbarItem label]];
            [toolbarItem setToolTip: toNSString(action->toolTip())];
            //
            [toolbarItem setTarget : self];
            [toolbarItem setAction : @selector(itemClicked:)];

            [groupItems addObject:toolbarItem];
            //
            [groupView setWidth:40.0 forSegment:i];
            //
            if (!action->icon().isNull())
            {
                QIcon icon = action->icon();
                QPixmap pixmap = icon.pixmap(16, 16);
                NSImage* image = toNSImage(pixmap);
                [groupView setImage:image forSegment:i];
            }
        }
        //
        [group setSubitems:groupItems];
        //
        //
        int groupViewWidth = actionCount * 40 + 8;
        [group setMinSize:NSMakeSize(groupViewWidth, 26)];
        [group setMaxSize:NSMakeSize(groupViewWidth, 26)];
        //
        [group setView:groupView];
        //
        return group;
    }
    else
    {
        NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];

        [toolbarItem setLabel: toNSString(toolButton->text())];
        [toolbarItem setPaletteLabel:[toolbarItem label]];
        [toolbarItem setToolTip: toNSString(toolButton->toolTip())];

        // load icon. ### use QDeclarativePixmap to support network urls.
        QPixmap pixmap;
        QUrl url = toolButton->iconSource();
        QString urlString = url.toString();
        if (urlString.startsWith("qrc")) {
            urlString.remove(0, 3);
            pixmap.load(urlString);
        } else {
            pixmap.load(url.toLocalFile());
        }

        // Pre-scaling the icon here gives better looking results.
        // Store the result in m_iconPixmap, toNSImage returns
        // a reference to and not a copy of the pixmap data.
        if (toolButton->m_iconPixmap.isNull() && !pixmap.isNull())
            toolButton->m_iconPixmap = pixmap;

        if (toolButton->m_iconPixmap.isNull() == false) {
            [toolbarItem setImage : toNSImage(toolButton->m_iconPixmap)];
        }

        [toolbarItem setTarget : self];
        [toolbarItem setAction : @selector(itemClicked:)];

        return toolbarItem;
    }
}

- (void) viewSizeChanged : (NSNotification*)notification
{
    Q_UNUSED(notification);
    // Noop for now.
}

- (void)addActionGroup:(QActionGroup *)actionGroup
{
    MacToolButton *button = new MacToolButton(actionGroup);
    button->setActionGroup(actionGroup);
    items->append(button);
}

- (void)addAction:(QAction *)action
{
    MacToolButton *button = new MacToolButton(action);
    button->setAction(action);
    items->append(button);
}

- (QAction *)addActionWithText:(const QString *)text
{
    QIcon nullIcon;
    return [self addActionWithText:text icon:&nullIcon];
}

- (QAction *)addActionWithText:(const QString *)text icon:(const QIcon *)icon
{
    QAction *action = new QAction(*icon, *text, 0);
    MacToolButton *button = new MacToolButton(action);
    button->setAction(action);
    items->append(button);
    return action;
}

- (QAction *)addStandardItem:(MacToolButton::StandardItem) standardItem
{
    QAction *action = new QAction(0);
    MacToolButton *button = new MacToolButton(action);
    button->setAction(action);
    button->setStandardItem(standardItem);
    items->append(button);
    return action;
}

- (QAction *)addAllowedActionWithText:(const QString *)text
{
    QIcon nullIcon;
    return [self addAllowedActionWithText:text icon:&nullIcon];
}

- (QAction *)addAllowedActionWithText:(const QString *)text icon:(const QIcon *)icon
{
    QAction *action = new QAction(*icon, *text, 0);
    MacToolButton *button = new MacToolButton(action);
    button->setAction(action);
    items->append(button);
    return action;
}

- (QAction *)addAllowedStandardItem:(MacToolButton::StandardItem)standardItem
{
    QAction *action = new QAction(0);
    MacToolButton *button = new MacToolButton(action);
    button->setAction(action);
    button->setStandardItem(standardItem);
    items->append(button);
    return action;
}

@end