defmodule Injector.Cmd do
  @switches [
    project: :string,
    packtools: :string,
  ]
  def main(args) do
    handler_progress()
    with options <- parse_args(args),
      project_cfg when is_binary(project_cfg) <- Keyword.get(options, :project) do
      run(options)
    end
  end

  def run(options) do
    project_cfg = Keyword.get(options, :project)
    load_project(project_cfg, options)
    |> Injector.Builder.build()
  end

  defp set_packtools(project, path) when is_binary(path) do
    %{project | packtools: path}
  end
  defp set_packtools(project, nil) do
    path = :code.priv_dir(:injector)
            |> List.to_string
            |> Path.join("jar")
    set_packtools(project, path)
  end

  defp parse_args(args) do
    {options, [], []} = OptionParser.parse(args, strict: @switches)
    options
  end

  def load_project(file, options) do
    true = Code.ensure_loaded?(Injector.SDKInfo)
    project = File.read!(file)
              |> Poison.decode!(as: %Injector.Project{}, keys: :atoms)
              |> set_packtools(Keyword.get(options, :packtools))
    
    base = Path.absname(file) |> Path.dirname
    :maps.update_with(:sdk_list, fn l ->
      for i <- l do
        %Injector.SDKInfo{} 
        |> Map.merge(i)
        |> normal_dirs([:path], base)
      end
    end, project)
    |> normal_dirs([:work_dir, :keystore, :apk_path, :packtools], base)
    |> Map.put(:id, :erlang.make_ref())
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

  defp handler_progress do
    Task.start_link fn ->
      stream = GenEvent.stream(Injector.Progress)

      for {_id, progress, type, _info} <- stream do
        IO.inspect "#{progress}: #{type}"
      end
    end
  end
end
