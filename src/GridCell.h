#import <UIKit/UIKit.h>
#import "Proc.h"
#import "Column.h"

@interface GridTableCell : UITableViewCell
{
	CGFloat firstCol;
}
@property (retain) NSMutableArray *labels;
@property (retain) NSMutableArray *dividers;
- (instancetype)initWithId:(NSString *)reuseIdentifier proc:(PSProc *)proc columns:(NSArray *)columns size:(CGSize)size;
+ (instancetype)cellWithId:(NSString *)reuseIdentifier proc:(PSProc *)proc columns:(NSArray *)columns size:(CGSize)size;
- (void)updateWithProc:(PSProc *)proc columns:(NSArray *)columns;
- (void)layoutSubviews;

@end


@interface GridHeaderView : UITableViewHeaderFooterView
{
}
@property (retain) NSMutableArray *labels;
@property (retain) NSMutableArray *dividers;
- (instancetype)initWithColumns:(NSArray *)columns size:(CGSize)size;
+ (instancetype)headerWithColumns:(NSArray *)columns size:(CGSize)size;

@end
