defmodule Injector.SDKInfo do
  defstruct [
    path: nil,
    class: nil,
    src: ["src"],
    classpath: ["libs"],
    meta_data: %{}, 
  ]
end
