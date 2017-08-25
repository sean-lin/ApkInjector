defmodule Injector.MergeYml do
  @write_opt [:binary, :write]

  def merge(%{do_not_compress: nil}=project), do: project
  def merge(%{do_not_compress: []}=project), do: project
  def merge(project) do
    extensions = project.do_not_compress
    
    yml = read_yml(project)
    dnc = Enum.filter(yml["doNotCompress"], fn x ->
      !Enum.any?(extensions, fn y ->
        String.ends_with?(x, y)
      end)
    end) ++ extensions
    yml = %{yml | "doNotCompress" => dnc}
    write_yml(project, yml)
    project
  end

  defp read_yml(project) do
    [_, yml] = Path.join(project.apk_dir, "apktool.yml")
               |> File.read!
               |> String.split("\n", parts: 2)
    YamlElixir.read_from_string yml
  end

  defp write_yml(project, doc) do
    Path.join(project.apk_dir, "apktool.yml")
    |> File.open!(@write_opt, fn fd ->
      data = Poison.encode!(doc)
      IO.write(fd, data)
    end)
  end
end
