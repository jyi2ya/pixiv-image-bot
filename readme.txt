===============
Pixiv Image Bot
===============

一个定时拉取 Pixiv RSS 并推送图片的机器人服务

功能特性
========

* 定时从 Pixiv RSS 获取最新图片
* 通过 OneBot API 推送图片到指定群组
* 基于 DeepDanbooru 实现标签过滤

依赖要求
========

* libmojolicious-perl
* libdata-printer-perl （其实不用，但是懒的删了。调试也方便）

配置说明
========

复制 settings.example 为 settings 并修改以下参数：

    ONEBOT_API=                   # OneBot API地址
    ONEBOT_API_TOKEN=             # API访问令牌
    TARGET_GROUP_ID=              # 目标群组ID
    TAGS_BLACKLIST=               # 标签黑名单(冒号分隔)
    TAGS_BLACKLIST_THRESHOLD=0.9  # 标签匹配阈值
    TIME_BUDGET=432000            # 图片保留时间(秒)
    RSS_CHANNELS=                 # RSS频道配置。具体名字参考 https://rakuen.thec.me/PixivRss/

部署方式
========

1. 安装依赖：

   sudo apt install libmojolicious-perl libdata-printer-perl

2. 修改配置

3. 启用服务：

   sudo systemctl enable --now ./pixiv-image-bot.service
   sudo systemctl enable --now ./pixiv-image-bot-sync.service
   sudo systemctl enable --now ./pixiv-image-bot-sync.timer
