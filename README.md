# Injector

A tool for packing libraries(third party sdks) to a apk

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `injector` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:injector, "~> 0.1.0"}]
    end
    ```

  2. Ensure `injector` is started before your application:

    ```elixir
    def application do
      [applications: [:injector]]
    end
    ```
# 感谢

一开始要做这个项目的时候，翻阅了很多 Android 构建的资料，边看边写。
做到一半的时候，突然看到 leenjewel 同学的blog，以及他做的 MySDK。
相逢恨晚啊，早看到了我就不会走那些弯路了。 把自己的代码做了大幅重构，
打包流程基本上最后变成了照抄 MySDK 了 :)

http://leenjewel.github.io/blog/2015/12/02/ye-shuo-android-apk-da-bao/
https://github.com/leenjewel/mysdk

想折腾的这一块的同学，强烈建议读读这篇文章，也可以试试使用 MySDK。

那为啥不直接用 MySDK 呢，主要有以下原因

* 我希望把这个库用在服务器端，可以实现多机多个 APK 并发打包。python 需要搞一堆脚手架系统。如果用 Elixir 来调用 Mysdk, 同样也要很多的支撑代码，还不如直接用 elixir 重写一遍，反正代码不多。
* 我只希望用 MySDK 的打包机制，管理机制和 Android 接口，我有自己的需求
* leenjewel 同学目测对 Python 并不是很熟悉，python部分的代码，PEP8 过不了，也不够 pythonic ，用我也需要重写一遍。

最后，这个项目我还是继续做下来了。

# Roadmap
接下来会想办法把我司的 EjoySDK 和其他SDK 对接的部分也整理开放出来，以及制作一个 Web 的管理系统。
