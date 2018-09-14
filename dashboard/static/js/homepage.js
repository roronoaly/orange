(function (L) {
    var _this = null;
    L.HOMEPAGE = L.HOMEPAGE || {};
    _this = L.HOMEPAGE = {
        data: {},

        init: function () {
            _this.loadConfigs("homepage", _this, true);
            _this.initEvents();
        },

        loadConfigs: function (type, context, page_load, callback) {
            var op_type = type;
            $.ajax({
                url: '/' + op_type + '/selectors',
                type: 'get',
                cache: false,
                data: {},
                dataType: 'json',
                success: function (result) {
                    if (result.success) {
                        L.Common.resetSwitchBtn(result.data.enable, op_type);
                        $("#switch-btn").show();
                        $("#view-btn").show();

                        var enable = result.data.enable;
                        var meta = result.data.meta;
                        var selectors = result.data.selectors;

                        //重新设置数据
                        context.data.enable = enable;
                        context.data.meta = meta;
                        context.data.selectors = selectors;

                        if (page_load) {//第一次加载页面
                            var selector_lis = $("#selector-list li");
                            if (selector_lis && selector_lis.length > 0) {
                                $(selector_lis[0]).click();
                            }
                        }

                        callback && callback();
                    } else {
                        L.Common.showErrorTip("错误提示", "查询" + op_type + "配置请求发生错误");
                    }
                },
                error: function () {
                    L.Common.showErrorTip("提示", "查询" + op_type + "配置请求发生异常");
                }
            });
        },
        initSyncDialog: function (type, context) {
            var op_type = type;
            var rules_key = "rules";

            $("#sync-btn").click(function () {
                $.ajax({
                    url: '/' + op_type + '/fetch_config',
                    type: 'get',
                    cache: false,
                    data: {},
                    dataType: 'json',
                    success: function (result) {
                        if (result.success) {
                            var d = dialog({
                                title: '确定要从存储中同步配置吗?',
                                width: 680,
                                content: '<pre id="preview_plugin_config"><code></code></pre>',
                                modal: true,
                                button: [{
                                    value: '取消'
                                }, {
                                    value: '确定同步',
                                    autofocus: false,
                                    callback: function () {
                                        $.ajax({
                                            url: '/' + op_type + '/sync',
                                            type: 'post',
                                            cache: false,
                                            data: {},
                                            dataType: 'json',
                                            success: function (r) {
                                                if (r.success) {
                                                    _this.loadConfigs(op_type, context);
                                                    return true;
                                                } else {
                                                    L.Common.showErrorTip("提示", r.msg || "同步配置发生错误");
                                                    return false;
                                                }
                                            },
                                            error: function () {
                                                L.Common.showErrorTip("提示", "同步配置请求发生异常");
                                                return false;
                                            }
                                        });
                                    }
                                }]
                            });
                            d.show();

                            $("#preview_plugin_config code").text(JSON.stringify(result.data, null, 2));
                            $('pre code').each(function () {
                                hljs.highlightBlock($(this)[0]);
                            });
                        } else {
                            L.Common.showErrorTip("提示", result.msg || "从存储中获取该插件配置发生错误");
                            return;
                        }
                    },
                    error: function () {
                        L.Common.showErrorTip("提示", "从存储中获取该插件配置请求发生异常");
                        return false;
                    }
                });

            });
        },
        initEvents: function () {
            var op_type = "homepage";
            L.Common.initViewAndDownloadEvent(op_type, _this);
            L.Common.initSwitchBtn(op_type, _this);//redirect关闭、开启
            _this.initSyncDialog(op_type, _this);//编辑规则对话框
        },
    };
}(APP));
