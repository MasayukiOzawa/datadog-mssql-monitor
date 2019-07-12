PowerShell で Datadog にメトリクスを送信します。  
(処理のベースは、[datadog-mssql-monitor](https://github.com/moaikids/datadog-mssql-monitor) を参考にさせていただきました)

conf.d 配下の yaml を読み込み、Datadog にメトリクスをおくります。  
[Azure Functions](https://azure.microsoft.com/ja-jp/services/functions/) からの実行を想定しており、実行には「local.settings.sample.json」の内容の環境変数の設定が必要となります。  
ローカルデバッグする場合は、local.settings.sample.json をlocal.settings.json にリネームし、各種環境変数を設定してください。

PowerShell Core が実行できる環境であれば、利用できるはずですので、Azure Functions 以外で実行する場合は、「run.ps1」を適宜修正して下さい。

### 使用しているライブラリ
#### [YamlDotNet](https://github.com/aaubry/YamlDotNet/)
* **用途 :** YAML のパース
> Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014 Antoine Aubry and contributors
> Released under the MIT license
> https://github.com/aaubry/YamlDotNet/blob/master/LICENSE
