defmodule Injector.Script do
  defstruct [
    project: nil,
    sdk: nil,
  ]

  def run(project, sdk_info, filename) do
    module_name = Module.concat(sdk_info.name,  :Script)

    functions = File.read!(filename) 
                |> Code.string_to_quoted!()
    
    Module.create(module_name, functions, [file: filename, line: 1])

    env = %__MODULE__{
      project: project,
      sdk: sdk_info,
    }

    %__MODULE__{project: project} = module_name.run(env)

    project
  end
end

defmodule Injector.Script.API do
  def refactor_class_to_package(env, class_name, target) do
    classes = String.split(class_name, ".")

    [file_prefix | class_path] = :lists.reverse(classes)
    class_path = :lists.reverse(class_path)
    
    pattern = "L" <> Enum.join(class_path, "/") <> "/(" <> file_prefix <> "\\$?\\d?);"
              |> Regex.compile!
  
    target_base_classes = env.project.package_name
                          |> List.to_string
                          |> String.split(".")

    target_base = Path.join([
      env.project.apk_dir, "smali"
      | target_base_classes])

    target_path = Path.join(target_base, target)
    File.mkdir_p! target_path

    target_pattern = "L" <> Enum.join(target_base_classes, "/") <> "/" <> target <> "/\\1;"

    glob = Path.join([env.project.apk_dir, "smali" | classes]) <> "*.smali"

    Path.wildcard(glob) |> Enum.each(fn file ->
      IO.inspect("refactor file " <> file)
      basename = Path.basename(file)
      data = File.read! file
      
      data = Regex.replace(pattern, data, target_pattern, global: true) 
      Path.join(target_path, basename) |> File.write!(data)

      File.rm!(file)
    end)
    env 
  end

  def update_android_manifest(%{project: project}=env, updater) do
      {doc, _} = String.to_charlist(project.manifest_path) 
                 |> :xmerl_scan.file([quiet: true])
      [root] = :xmerl_xpath.string('/manifest[1]', doc)
  
      new_root = updater.(root) 

      xml_prolog = ~s(<?xml version="1.0" encoding="utf-8" standalone="no"?>)
      File.open!(project.manifest_path, [:binary, :write], fn fd ->
        data = :xmerl.export_simple([new_root], :xmerl_xml, prolog: xml_prolog)
        IO.write(fd, data)
      end)
      env
  end

  defdelegate change_element(root, name, cb), to: Injector.AndroidManifest
  defdelegate change_attribute(root, name, cb), to: Injector.AndroidManifest
end
