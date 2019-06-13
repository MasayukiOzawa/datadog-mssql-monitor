PowerShell で Datadog にメトリクスを送信します。  
(処理のベースは、[datadog-mssql-monitor](https://github.com/moaikids/datadog-mssql-monitor) を参考にさせていただきました)

YAML の読み込みに [YamlDotnet](https://www.nuget.org/stats) を使用しているため、lib 配下にモジュールをダウンロードして、 DLL を配置する必要があります。

conf.d 配下の yaml を読み込み、Datadog にメトリクスをおくります。