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
    |> work_dir(project_cfg)
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
    :maps.update_with(:sdk_list, fn l ->
      for i <- l do
        %Injector.SDKInfo{} |> Map.merge(i)
      end
    end, project)
  end

  defp work_dir(%{work_dir: <<"/", _::binary>>}=project, _project_cfg) do
    project
  end
  defp work_dir(project, project_cfg) do
    dir = Path.absname(project_cfg)
          |> Path.dirname
          |> Path.join(project.work_dir)
          |> Path.absname
    Map.put(project, :work_dir, dir)
  end
end
