#import "Compat.h"
#import "SockViewController.h"
#import "GridCell.h"
#import "Column.h"
#import "Sock.h"

NSString *ColumnModeName[ColumnModes] = {@"Summary", @"Threads", @"Open files", @"Modules"};

@implementation SockViewController
{
	PSProc *proc;
	NSString *procName;
	GridHeaderView *header;
	NSArray *columns;
	NSTimer *timer;
	PSSockArray *socks;
	PSColumn *sortColumn;
	BOOL sortDescending;
	CGFloat timerInterval;
	NSUInteger configId;
	column_mode_t viewMode;
	CGFloat fullRowHeight;
}

- (void)popupMenuTappedItem:(NSInteger)item
{
    // Skip ports now
    if (item == 3) {
        item++;
    }
	if (viewMode != item) {
		// Mode changed - need to reset all information
		viewMode = self.popupMenuSelected = item;
		socks = [PSSockArray psSockArrayWithProc:proc];
		[self configureMode];
		[[NSUserDefaults standardUserDefaults] setInteger:viewMode forKey:@"ProcInfoMode"];
		[self refreshSocks:nil];
	}
}

- (instancetype)initWithProc:(PSProc *)_proc
{
	self = [super init];
	proc = _proc;
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back"
		style: UIBarButtonItemStyleDone target:self action:@selector(backWithoutAnimation)];

	viewMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"ProcInfoMode"];
	NSMutableArray *modeItems = [NSMutableArray arrayWithObjects:ColumnModeName count:ColumnModes - 1];
	modeItems[ColumnModeThreads] = [modeItems[ColumnModeThreads] stringByAppendingFormat:@" (%u)", proc.threads];
	modeItems[ColumnModeFiles  ] = [modeItems[ColumnModeFiles  ] stringByAppendingFormat:@" (%u)", proc.files];
//	modeItems[ColumnModePorts  ] = [modeItems[ColumnModePorts  ] stringByAppendingFormat:@" (%u)", proc.ports];
//	modeItems[ColumnModeModules] = [modeItems[ColumnModeModules] stringByAppendingFormat:@" (%u)", proc.modules];
	[self popupMenuWithItems:modeItems selected:viewMode aligned:UIControlContentHorizontalAlignmentRight];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                              initWithImage:[UIImage imageNamed:@"UIButtonBarHamburger"]
                                              style:UIBarButtonItemStylePlain
                                              target:self
                                              action:@selector(popupMenuToggle)];
	[self.tableView setSeparatorInset:UIEdgeInsetsZero];

	self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.sectionHeaderHeight = 24;
	fullRowHeight = self.tableView.rowHeight;
	configId = 0;
}

- (void)refreshSocks:(NSTimer *)_timer
{
	// Rearm the timer: this way the timer will wait for a full interval after each 'fire'
	if (timerInterval >= 0.1) {
		if (timer.isValid)
			[timer invalidate];
		timer = [NSTimer scheduledTimerWithTimeInterval:timerInterval target:self selector:@selector(refreshSocks:) userInfo:nil repeats:NO];
	}
	// Update titlebar
	[proc update];
	self.navigationItem.title = [procName stringByAppendingFormat:@" (CPU %.1f%%)", (float)proc.pcpu / 10];
	// Update tableview
	if ([socks refreshWithMode:viewMode] && socks.proc.pid != 0)
		self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:1 green:0.7 blue:0.7 alpha:1];
	[socks sortUsingComparator:sortColumn.sort desc:sortDescending];
	[self.tableView reloadData];
	// First time refresh?
	if (_timer == nil) {
		// We don't need info about new sockets, they are all new :)
		[socks setAllDisplayed:ProcDisplayNormal];
		// When mode changes return to top
		if (socks.count)
			[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
				atScrollPosition:UITableViewScrollPositionNone animated:NO];
	} else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AutoJumpNewProcess"]) {
		// If there's a new socket, scroll to it
		NSUInteger
			idx = [socks indexOfDisplayed:ProcDisplayStarted];
		if (idx == NSNotFound)
			idx = [socks indexOfDisplayed:ProcDisplayTerminated];
		if (idx != NSNotFound)
			[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]
				atScrollPosition:UITableViewScrollPositionNone animated:YES];
	}
}

- (void)sortHeader:(UIGestureRecognizer *)gestureRecognizer
{
	CGPoint loc = [gestureRecognizer locationInView:header];
	for (PSColumn *col in columns) {
		if (loc.x > col.width) {
			loc.x -= col.width;
			continue;
		}
		sortDescending = sortColumn == col ? !sortDescending : col.style & ColumnStyleSortDesc;
		[header sortColumnOld:sortColumn New:col desc:sortDescending];
		sortColumn = col;
		[[NSUserDefaults standardUserDefaults] setInteger:col.tag forKey:[NSString stringWithFormat:@"Mode%dSortColumn", viewMode]];
		[[NSUserDefaults standardUserDefaults] setBool:sortDescending forKey:[NSString stringWithFormat:@"Mode%dSortDescending", viewMode]];
		[timer fire];
		break;
	}
}

- (void)configureMode
{
	// When configId changes, all cells are reconfigured
	configId++;
	columns = [PSColumn psGetTaskColumnsWithWidth:self.tableView.bounds.size.width mode:viewMode];
	// Find sort column and create table header
	NSString *key = [NSString stringWithFormat:@"Mode%dSortColumn", viewMode];
	sortColumn = [PSColumn psTaskColumnWithTag:[[NSUserDefaults standardUserDefaults] integerForKey:key] forMode:viewMode];
	if (!sortColumn) {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
		sortColumn = [PSColumn psTaskColumnWithTag:[[NSUserDefaults standardUserDefaults] integerForKey:key] forMode:viewMode];
		if (!sortColumn) sortColumn = columns[0];
	}
	sortDescending = [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"Mode%dSortDescending", viewMode]];
	header = [GridHeaderView headerWithColumns:columns size:CGSizeMake(0, self.tableView.sectionHeaderHeight)];
	[header sortColumnOld:nil New:sortColumn desc:sortDescending];
	[header addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sortHeader:)]];
//	self.tableView.rowHeight = viewMode == ColumnModeModules ? fullRowHeight : fullRowHeight * 0.6;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    socks = [PSSockArray psSockArrayWithProc:proc];
    procName = [proc.executable lastPathComponent];
    [self configureMode];
    // Refresh interval
    timerInterval = [[NSUserDefaults standardUserDefaults] floatForKey:@"UpdateInterval"];
    [self refreshSocks:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if (timer.isValid)
        [timer invalidate];
    socks = nil;
    header = nil;
    columns = nil;
    proc = nil;
}

- (BOOL)shouldAutorotate {
    return [self.navigationController supportedInterfaceOrientations];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context)
    {
        UIInterfaceOrientation fromInterfaceOrientation = [UIApplication sharedApplication].windows[0].windowScene.interfaceOrientation;
        [self didRotate:fromInterfaceOrientation];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
    {

    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)didRotate:(UIInterfaceOrientation)fromInterfaceOrientation
{
    UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].windows[0].windowScene.interfaceOrientation;
    if ((fromInterfaceOrientation == UIInterfaceOrientationPortrait || fromInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) &&
        (deviceOrientation == UIInterfaceOrientationPortrait || deviceOrientation == UIInterfaceOrientationPortraitUpsideDown))
        return;
    if ((fromInterfaceOrientation == UIInterfaceOrientationLandscapeLeft || fromInterfaceOrientation == UIInterfaceOrientationLandscapeRight) &&
        (deviceOrientation == UIInterfaceOrientationLandscapeLeft || deviceOrientation == UIInterfaceOrientationLandscapeRight))
        return;
    // Size changed - need to redraw
    [self configureMode];
    [timer fire];
}

- (IBAction)backWithoutAnimation
{
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark -
#pragma mark Table view data source

// Customize the number of sections in the table view.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

// Section header/footer will be used as a grid header/footer
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{ return header; }

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{ return self.tableView.sectionHeaderHeight; }

// Data is acquired from PSProcArray
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return socks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	PSSock *sock = nil;
	if (indexPath.row < socks.count && columns && columns.count)
		sock = socks[indexPath.row];
	GridTableCell *cell = [tableView dequeueReusableCellWithIdentifier:[GridTableCell reuseIdWithIcon:NO]];
	if (cell == nil)
		cell = [GridTableCell cellWithIcon:NO];
	[cell configureWithId:configId columns:columns];
	if (sock)
		[cell updateWithSock:sock columns:columns];
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	display_t display = socks[indexPath.row].display;
	if (display == ProcDisplayTerminated)
		cell.backgroundColor = [UIColor colorWithRed:1 green:0.7 blue:0.7 alpha:1];
	else if (display == ProcDisplayStarted)
		cell.backgroundColor = [UIColor colorWithRed:0.7 green:1 blue:0.7 alpha:1];
	else if (indexPath.row & 1)
        cell.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:.15 green:.15 blue:.15 alpha:1];
            }else{
                return [UIColor colorWithRed:.95 green:.95 blue:.95 alpha:1];
            }
        }];
    else
        cell.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor blackColor];
            }else{
                return [UIColor whiteColor];
            }
        }];
}

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	PSSockSummary *sock = (PSSockSummary *)socks[indexPath.row];
	if (!sock)
		return;
	NSString *title = (viewMode == ColumnModeSummary) ? sock.name : ColumnModeName[viewMode],
		   *message = (viewMode == ColumnModeSummary) ? [NSString stringWithFormat:@"%@\n\n%@", sock.col.getData(sock.proc),
		   [sock.col.descr substringWithRange:NSMakeRange(0, [sock.col.descr lineRangeForRange:NSMakeRange(0,1)].length-1)]] :
					  (viewMode == ColumnModeModules) ? sock.name : sock.description;
//	if (viewMode == ColumnModePorts)
//		message = [[message stringByReplacingOccurrencesOfString:@" <" withString:@"\n<"] stringByReplacingOccurrencesOfString:@" >" withString:@"\n>"];
	UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning
{
	// Relinquish ownership of anything that can be recreated in viewDidLoad or on demand.
	if (timer.isValid)
		[timer invalidate];
	header = nil;
	sortColumn = nil;
	socks = nil;
	columns = nil;
	[super didReceiveMemoryWarning];
}

- (void)dealloc
{
	if (timer.isValid)
		[timer invalidate];
}

@end
