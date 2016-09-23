defmodule CmdTest do
  use ExUnit.Case

  test "load config" do
    project = Injector.Cmd.load_project("test/test.json", [project: "test/test.json"])
    assert project.project_name == "test_demo"
  end
end
