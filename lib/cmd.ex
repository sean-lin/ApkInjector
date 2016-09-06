defmodule Injector.Cmd do
  @switches [
    project: :string
  ]
  def main(args) do
    with options <- parse_args(args),
      project_cfg <- Keyword.get(options, :project) do
      run(project_cfg)
    end
  end

  def run(project_cfg) do

    load_project(project_cfg)
    |> Injector.Builder.build()
  end

  defp parse_args(args) do
    {options, [], []} = OptionParser.parse(args, strict: @switches)
    options
  end

  def load_project(file) do
    Code.ensure_loaded?(Injector.SDKInfo)
    project = File.read!(file)
              |> Poison.decode!(as: %Injector.Project{}, keys: :atoms!)
    
    base = Path.absname(file) |> Path.dirname
    :maps.update_with(:sdk_list, fn l ->
      for i <- l do
        %Injector.SDKInfo{} 
        |> Map.merge(i)
        |> normal_dirs([:path], base)
      end
    end, project)
    |> normal_dirs([:work_dir, :keystore, :apk_path], base)
  end

  defp normal_dirs(project, dirs, base) do
    Enum.reduce(dirs, project, fn key, acc ->
      path = Map.get(acc, key) |> abspath(base)
      Map.put(acc, key, path)
    end)
  end

  defp abspath(<<"/", _::binary>>=path, _base) do
    path
  end
  defp abspath(path, base) do
    Path.join(base, path) |> Path.absname
  end
end
