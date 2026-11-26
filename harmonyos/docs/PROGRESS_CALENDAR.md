# v0.9.3c 追剧与日历
- 下一集：对已缓存的已播普通集目录应用现有本机物化状态，按 season/number 取首个未看。全部缓存目录参与，非最近 12 部限制。不把云端观看数量推断为具体集。
- 最近操作按现有 SQLite 事件序号；剩余集数从少到多；片名排序。无需引入经验性推荐权重。
- 个人日历：Trakt my/shows、my/movies，七日窗口，服务端 UTC 查询覆盖本地日期边界。剧集时间转当地，电影 date-only 不人为偏移。过滤、分页、会话校验；未知日期不填造。
- 只读新增视图。既有分集自动同步独立运行；没有新增云端写入入口。没有修改数据库结构。无缓存目录的云端剧集仍可从云端记录进入详情后下载目录。
- 未实现原版完整云端 Up Next、隐藏/归档、通知、地区上映表。设备真机日历接口权限与返回形状需验证。

## v0.9.3c.1 修复
原版 [CalendarMoviesItemsCase](https://github.com/trakt/showly/blob/e08cb90ba0205ed9401a11265b912b0302f253b5/ui-progress-movies/src/main/java/com/michaldrabik/ui_progress_movies/calendar/cases/items/CalendarMoviesItemsCase.kt) 合并已看和待看，按 movie.released 过滤；未来无上限。鸿蒙电影页改用完整分页个人电影库 extended=full；稳定 ID 去重、活动与会话校验，日期按 YYYY-MM-DD 比较。明确本机标记的电影也可列出；旧未知本机条目不推断。日期未知不丢弃，提供逐条补查。缓存仅当前会话内存，非持久缓存。过去日期增加更早上映组，原版近期组到90天。保留剧集七日窗口，不改变同步、数据库或账号授权。无全站电影入口。
