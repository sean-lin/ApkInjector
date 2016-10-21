defmodule Injector.SDKInfo do
  defstruct [
    name: nil,
    path: nil,
    class: nil,
    src: ["src"],
    classpath: ["libs"],
    meta_data: %{}, 
    ability: [],
  ]
end
