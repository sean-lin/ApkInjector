defmodule Injector do
  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_, _) do
    import Supervisor.Spec, warn: false

    children = [
      worker(GenEvent, [[name: Injector.Progress]]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Injector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule Injector.Project do
  @derive [Poison.Encoder]
  defstruct [
    id: nil,                # required
    project_name: nil,
    package_name: nil,
    project_desc: "",
    android_sdk_root: nil,  # required
    android_platform: nil,  # required
    packtools: nil,

    sdk_list: [],
    meta_data: %{},

    work_dir: nil,
    apk_dir: nil,
    apk_lib_dir: nil,
    apk_libs_dir: nil,
    apk_gen_dir: nil,
    apk_bin_dir: nil,

    base_package: nil,
    aapt: nil, dx: nil, zipalign: nil,
    java: nil, javac: nil, jar: nil, jarsigner: nil,
    apktool: nil, baksmali: nil,

    apk_path: nil,
    keystore: nil, storepass: nil, alias: nil, keypass: nil,

    apk_unsigned_path: nil,
    apk_signed_path: nil,
    apk_align_path: nil,

    manifest: nil,
    manifest_path: nil,
  ]
end

defmodule Injector.AndroidSDK do
end

defmodule Injector.Builder do
  def build(project) do
    project = project
              |> sync_event(:init, :start)
              |> normal_android_sdk
              |> normal_jdk
              |> normal_output_apk
              |> normal_apktool
              |> sync_event(:init, :end)
              |> sync_event_wrapper(&decode_apk/1, :decode_apk)
              |> sync_event_wrapper(&make_dirs/1, :make_dirs)
              |> sync_event_wrapper(&parse_manifest/1, :parse_manifest)
              |> sync_event_wrapper(&write_sdk_config/1, :write_sdk_config)  # 先写这个， 因为manifest接下来就会改掉
              |> inject_sdks
              |> sync_event_wrapper(&write_manifest/1, :write_manifest)
              |> sync_event_wrapper(&prebuild_sdks/1, :prebuild_sdks)
              |> sync_event_wrapper(&prebuild_project/1, :prebuild_project)
              |> sync_event_wrapper(&build_jar/1, :build_jar)
              |> sync_event_wrapper(&dex_jar/1, :build_dex)
              |> sync_event_wrapper(&aapt_res_assets/1, :build_assets)
              |> sync_event_wrapper(&baksmali/1, :baksmali)
              |> run_sdk_scripts
              |> sync_event_wrapper(&build_apk/1, :build_apk)
              |> sign_apk
              |> clean

    IO.puts Injector.AndroidManifest.render(project.manifest)
  end

  defp decode_apk(project) do
    args = [
      "-jar", "-Xmx512M", "-Djava.awt.headless=true",
      project.apktool, "-f",
      "--output", project.apk_dir,
      "d", project.apk_path,
    ]
    {output, 0} = System.cmd project.java, args 
    IO.puts output
    project
  end

  defp parse_manifest(project) do
    manifest_path = Path.join(project.apk_dir, "AndroidManifest.xml")
    manifest = Injector.AndroidManifest.file(manifest_path)
    {project, manifest} = case project.package_name do
      nil -> {%{project | package_name: manifest.package}, manifest}
      name ->
        # package_name 用 Charlist 保证后面处理起来方便
        name = String.to_charlist(name)
        {%{project | package_name: name}, %{manifest | package: name}}
    end
    
    project
    |> Map.put(:manifest, manifest)
    |> Map.put(:manifest_path, manifest_path)
  end
  
  @write_opt [:binary, :write]

  defp write_manifest(project) do
    File.open!(project.manifest_path, @write_opt, fn fd ->
      data = Injector.AndroidManifest.render(project.manifest)
      IO.write(fd, data)
    end)
    project
  end

 
  # {
  #   "sdks": [
  #     {
  #       "class": "com.ejoy.unisdk_adapter.testsdk.TestSDK",
  #       "meta": { },
  #       "ability": ["ACCOUNT", "PAY"]
  #     }
  #   ]
  # }

  defp write_sdk_config(project) do
    config_dir = Path.join([project.apk_assets_dir, "unisdk"])
    File.mkdir_p(config_dir)
    config_path = Path.join(config_dir, "sdkconfig.json")

    items = for sdk <- project.sdk_list do
      %{
        class: sdk.class,
        meta: sdk.meta_data,
        ability: sdk.ability,
      }
    end
    doc = %{
      main_activity: to_string(project.manifest.main_activity_name),
      package: to_string(project.manifest.package), 
      sdks: items,
      meta: project.meta_data
    }

    File.open!(config_path, @write_opt, fn fd ->
      data = Poison.encode!(doc)
      IO.write(fd, data)
    end)
    project
  end

  defp normal_output_apk(project) do
    project
    |> Map.put(:apk_dir, Path.join(project.work_dir, "out"))
    |> Map.put(:apk_lib_dir, Path.join([project.work_dir, "out", "lib"]))
    |> Map.put(:apk_libs_dir, Path.join([project.work_dir, "out", "libs"]))
    |> Map.put(:apk_gen_dir, Path.join([project.work_dir, "out", "gen"]))
    |> Map.put(:apk_bin_dir, Path.join([project.work_dir, "out", "bin"]))
    |> Map.put(:apk_res_dir, Path.join([project.work_dir, "out", "res"]))
    |> Map.put(:apk_assets_dir, Path.join([project.work_dir, "out", "assets"]))
    |> Map.put(:apk_unsigned_path, Path.join(project.work_dir, "out.unsigned.apk"))
    |> Map.put(:apk_signed_path, Path.join(project.work_dir, "out.signed.apk"))
    |> Map.put(:apk_align_path, Path.join(project.work_dir, "out.align.apk"))
  end

  defp normal_android_sdk(project) do
    tools = [:aapt, :dx, :zipalign]

    build_tools_dir = Path.join(project.android_sdk_root, "build-tools")

    version = File.ls!(build_tools_dir)
              |> Enum.map(fn x -> 
                v = String.split(x, ".")
                    |> Enum.map(&String.pad_leading(&1, 6, "0")) 
                    |> Enum.join()
                {x, v} 
              end)
              |> Enum.max_by(fn {_, v} -> v end)
              |> elem(0)

    found_dir = Path.join(build_tools_dir, version)
    project = tools
              |> Enum.reduce(project, fn tool, acc ->
                tool_path = Path.join(found_dir, Atom.to_string(tool)) |> Path.absname
                Map.put(acc, tool, tool_path)
              end)
    
    base_package = Path.join(
      [project.android_sdk_root, 
       "platforms", 
       "android-" <> project.android_platform, 
       "android.jar"])
    
    Map.put(project, :base_package, base_package)
  end

  defp normal_jdk(project) do
    [:java, :javac, :jar, :jarsigner]
    |> Enum.reduce(project, fn x, acc ->
      path = Atom.to_charlist(x)
              |> :os.find_executable
              |> List.to_string
      Map.put(acc, x, path) 
    end)
  end

  defp normal_apktool(project) do
    project
    |> Map.put(:apktool, Path.join(project.packtools, "apktool.jar"))
    |> Map.put(:baksmali, Path.join(project.packtools, "baksmali.jar"))
  end

  defp make_dirs(project) do
    File.mkdir_p(project.apk_lib_dir)
    File.mkdir_p(project.apk_libs_dir)
    File.mkdir_p(project.apk_gen_dir)
    File.mkdir_p(project.apk_bin_dir)
    File.mkdir_p(project.apk_res_dir)
    File.mkdir_p(project.apk_assets_dir)
    project
  end

  defp inject_sdks(project) do
    Enum.reduce(project.sdk_list, project, fn x, acc ->
      inject_sdk(acc, x)
    end)
  end

  defp inject_sdk(project, sdk) do
    project
    |> sync_event(:inject_sdk, :start, %{name: sdk.name})
    |> inject_sdk_manifest(sdk)
    |> inject_sdk_lib(sdk)
    |> sync_event(:inject_sdk, :end, %{name: sdk.name})
  end

  defp inject_sdk_manifest(project, sdk) do
    meta_data = %{
      "main_activity": project.manifest.main_activity_name,
      "package": project.manifest.package} 
      |> Map.merge(project.meta_data)
      |> Map.merge(sdk.meta_data)

    manifest = Path.join(sdk.path, "sdk_android_manifest.xml")
                |> EEx.eval_file(Map.to_list(meta_data))
                |> Injector.AndroidManifest.string

    %{project | manifest: Injector.AndroidManifest.merge(project.manifest, manifest)}
  end

  defp inject_sdk_lib(project, sdk) do
    ["lib", "libs", "jni"] |> Enum.each(fn x -> 
      cp_wildcard(Path.join(sdk.path, x), "/**/*.so", project.apk_lib_dir)
    end)
    project
  end

  defp prebuild_sdks(project) do
    project.sdk_list |> Enum.each(fn sdk ->
      manifest = Path.join(sdk.path, "AndroidManifest.xml")
      build_package_R(project, manifest, true)
      classpath = find_file(sdk.path, "/**/*.jar", sdk.classpath)
      files = find_file(sdk.path, "/**/*.java", sdk.src)
      build_java_class(project, classpath, files)
    end)
    project
  end

  defp prebuild_project(project) do
    project
    |> build_package_R(project.manifest_path)
    |> build_java_class([], 
      Path.wildcard(project.apk_gen_dir <> "/**/*.java"))
  end

  defp aapt_all(project, dir) do
    project.sdk_list
    |> Enum.map(fn x -> Path.join(x.path, dir) end)
    |> Enum.filter(fn dir -> File.exists?(dir) end)
  end

  defp build_package_R(project, manifest_path, non_constant_id \\ false) do
    cmdline = [
      project.aapt,
      "package", "-m",
      "--auto-add-overlay",
      "-J", project.apk_gen_dir,
      "-M", manifest_path,
      "-I", project.base_package, 
      "-S", project.apk_res_dir
    ]
    cmdline = cmdline ++ append_opts("-S", aapt_all(project, "res"))

    cmdline = case non_constant_id do
      true -> cmdline ++ ["--non-constant-id"]
      false -> cmdline
    end
    run_cmd(project, cmdline)
  end
  
  defp build_java_class(project, _classpath, []) do
    project
  end
  defp build_java_class(project, classpath, files) do
    cmdline = [
      project.javac,
      "-target", "1.7",
      "-source", "1.7",
      "-bootclasspath", project.base_package,
      "-d", project.apk_bin_dir,
      "-cp", Enum.join([project.apk_gen_dir | classpath], ":")
      | files]
    run_cmd(project, cmdline)
  end
  
  defp find_file(root_path, glob, dirs) do
    dirs |> Enum.map(fn x ->
      dir = Path.join(root_path, x)
      Path.wildcard(dir <> glob)
    end) |> List.flatten
  end

  defp build_jar(project) do
    cmdline = [
      project.jar,
      "cvf",
      Path.join(project.apk_bin_dir, "classes.jar"),
      "-C", project.apk_bin_dir, "."
    ]
    run_cmd(project, cmdline)
  end

  defp dex_jar(project) do
    jars = project.sdk_list |> Enum.map(fn sdk ->
      find_file(sdk.path, "/**/*.jar", sdk.classpath)
    end) |> List.flatten

    jar_path = Path.join(project.apk_bin_dir, "classes.jar")

    cmdline = [
      project.dx,
      "--dex",
      "--output", Path.join(project.apk_bin_dir, "classes.dex"),
      jar_path | jars
    ]

    
    project = run_cmd(project, cmdline)
    
    File.rm!(jar_path)

    project
  end

  defp aapt_res_assets(project) do
    resources_apk = Path.join(project.work_dir, "resources.ap_")
    cmdline = [
      project.aapt,
      "package",
      "-f",
      "--auto-add-overlay",
      "-M", project.manifest_path,
      "-I", project.base_package,
      "-F", resources_apk,
      "-S", project.apk_res_dir,
      "-A", project.apk_assets_dir
    ]
    cmdline = cmdline ++ append_opts("-S", aapt_all(project, "res"))
    cmdline = cmdline ++ append_opts("-A", aapt_all(project, "assets"))
    
    run_cmd(project, cmdline)

    resources_out = Path.join(project.work_dir, "resources_out")
    cmdline = [
      project.java, "-jar",
      project.apktool,
      "-f",
      "d", resources_apk,
      "-o", resources_out,
    ]
    run_cmd(project, cmdline)
    
    replace_dir(project.apk_res_dir, Path.join(resources_out, "res"))
    replace_dir(project.apk_assets_dir, Path.join(resources_out, "assets"))
    project
  end

  defp baksmali(project) do
    smali_dir = Path.join(project.apk_dir, "smali")
    dex_dir = Path.join(project.apk_bin_dir, "classes.dex")
    cmdline = [
      project.java, "-jar",
      project.baksmali,
      "-o", smali_dir, dex_dir
    ]

    project = run_cmd(project, cmdline)
    
    File.rm!(dex_dir)
    
    project
  end

  defp run_sdk_scripts(project) do
    Enum.reduce(project.sdk_list, project, fn x, acc ->
      run_sdk_script(acc, x)
    end)
  end

  defp run_sdk_script(project, sdk) do
    project
    |> sync_event(:run_scrip, :start, %{name: sdk.name})
    |> try_run_script(sdk)
    |> sync_event(:run_scrip, :end, %{name: sdk.name})
  end


  defp try_run_script(project, sdk) do
    script = Path.join(sdk.path, "script.exs")
    if File.exists? script do
      Injector.Script.run(project, sdk, script)
    else
      project
    end
  end

  defp build_apk(project) do
    cmdline = [
      project.java, "-jar",
      "-Xmx512M", "-Djava.awt.headless=true",
      project.apktool, "-f",
      "--output", project.apk_unsigned_path,
      "b", project.apk_dir,
    ]
    run_cmd(project, cmdline)
  end

  defp sign_apk(%{keystore: nil}=project) do
    project
  end
  defp sign_apk(project) do
    sync_event(project, :sign_apk, :start)
    cmdline = [
      project.jarsigner,
      "-digestalg", "SHA1",
      "-sigalg", "MD5withRSA",
      "-keystore", project.keystore,
      "-storepass", project.storepass,
      "-keypass", project.keypass,
      "-signedjar", project.apk_signed_path,
      project.apk_unsigned_path, project.alias,
    ]
    run_cmd(project, cmdline)

    cmdline = [
      project.zipalign,
      "-f",
      "4",
      project.apk_signed_path,
      project.apk_align_path,
    ]
    run_cmd(project, cmdline)
    |> sync_event(:sign_apk, :end)
  end

  defp clean(project) do
    project
  end

  defp run_cmd(project, [cmd | args]=cmdline) do
    IO.inspect(Enum.join(cmdline, " "))
    {_output, 0} = System.cmd(cmd, args)
    project
  end

  defp cp_wildcard(base, glob, dest_base) do
    Path.wildcard(base <> glob)
    |> Enum.map(fn f -> 
      relative = Path.relative_to(f, base)
      File.cp_r!(f, Path.join(dest_base, relative), fn _, _ -> false end)
    end)
  end

  defp replace_dir(target, from) do
    if File.exists?(from) do
      File.rm_rf(target)
      File.cp_r!(from, target)
    end
  end

  defp append_opts(switch, args) do
    Enum.map(args, fn x ->
      [switch, x]
    end) |> :lists.flatten
  end

  defp sync_event(project, progress, type, info \\ nil) do
    GenEvent.notify(
      Injector.Progress, 
      {project.id, progress, type, info})
    project
  end

  defp sync_event_wrapper(project, func, progress) do
    project
    |> sync_event(progress, :start)
    |> func.()
    |> sync_event(progress, :end)
  end
end
