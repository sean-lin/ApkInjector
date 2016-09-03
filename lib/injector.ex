defmodule Injector do
end

defmodule Injector.Project do
  @derive [Poison.Encoder]
  defstruct [
    project_name: nil,
    project_desc: "",
   
    sdk_list: [],
    meta_data: %{},

    work_dir: nil,
    apk_dir: nil,
    apk_lib_dir: nil,
    apk_libs_dir: nil,
    apk_gen_dir: nil,
    apk_bin_dir: nil,

    android_sdk_root: nil,  # required
    android_platform: nil,  # required

    base_package: nil,
    aapt: nil, dx: nil, zipalign: nil,
    java: nil, javac: nil, jar: nil, jarsigner: nil,
    apktool: nil, baksmali: nil,

    apk_path: nil,
    apk_unsigned_path: nil,
    apk_signed_path: nil,
    keystore: nil, storepass: nil, alias: nil, keypass: nil,

    manifest: nil,
    manifest_path: nil,
  ]
end

defmodule Injector.AndroidSDK do
end

defmodule Injector.Builder do
  def build(project) do
    project = project
              |> normal_android_sdk
              |> normal_jdk
              |> normal_output_apk
              |> normal_apktool
              |> decode_apk
              |> make_dirs
              |> parse_manifest
              |> inject_sdks
              |> write_manifest
              |> write_sdk_config
              |> prebuild_sdks
              |> prebuild_project
              |> build_jar
              |> dex_jar
              |> aapt_res_assets
              |> build_apk
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
    project
    |> Map.put(:manifest, Injector.AndroidManifest.file(manifest_path))
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

  # <resources>
  #     <string-array name="sdkNames">
  #         <item>com.ejoy.sdk<item>
  #     </string-array>
  # </resources>
  defp write_sdk_config(project) do
    xml_prolog = ~s(<?xml version="1.0" encoding="utf-8"?>)
    xml_path = Path.join([project.apk_res_dir, "values", "injector_sdk.xml"])

    items = for sdk <- project.sdk_list do
      {:item, [], [String.to_charlist(sdk.class)]}
    end
    doc = {:resources, [], [
      {:"string-array", [name: "sdkNames"], items},
    ]}
    File.open!(xml_path, @write_opt, fn fd ->
      data = :xmerl.export_simple([doc], :xmerl_xml, prolog: xml_prolog)
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
    |> Map.put(:apk_asserts_dir, Path.join([project.work_dir, "out", "asserts"]))
    |> Map.put(:apk_unsigned_path, Path.join(project.work_dir, "out.unsigned.apk"))
    |> Map.put(:apk_signed_path, Path.join(project.work_dir, "out.signed.apk"))
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
    dir = :code.priv_dir(:injector) |> List.to_string
    project
    |> Map.put(:apktool, Path.join([dir, "jar", "apktool.jar"]))
    |> Map.put(:baksmali, Path.join([dir, "jar", "baksmali.jar"]))
  end

  defp make_dirs(project) do
    File.mkdir_p(project.apk_lib_dir)
    File.mkdir_p(project.apk_libs_dir)
    File.mkdir_p(project.apk_gen_dir)
    File.mkdir_p(project.apk_bin_dir)
    File.mkdir_p(project.apk_res_dir)
    File.mkdir_p(project.apk_asserts_dir)
    project
  end

  defp inject_sdks(project) do
    Enum.reduce(project.sdk_list, project, fn x, acc ->
      inject_sdk(acc, x)
    end)
  end

  defp inject_sdk(project, sdk) do
    project
    |> inject_sdk_manifest(sdk)
    |> inject_sdk_lib(sdk)
  end

  defp inject_sdk_manifest(project, sdk) do
    manifest = Path.join(sdk.path, "sdk_android_manifest.xml")
                |> EEx.eval_file(Map.to_list(project.meta_data))
                |> Injector.AndroidManifest.string

    %{project | manifest: Injector.AndroidManifest.merge(project.manifest, manifest)}
  end

  defp inject_sdk_lib(project, sdk) do
    ["lib", "libs"] |> Enum.each(fn x -> 
      cp_wildcard(Path.join(sdk.path, x), "/**/*.so", project.apk_lib_dir)
    end)
    sdk.classpath |> Enum.each(fn x ->
      cp_wildcard(Path.join(sdk.path, x), "/**/*.jar", project.apk_libs_dir)
    end)
    project
  end

  defp prebuild_sdks(project) do
    project.sdk_list |> Enum.each(fn sdk ->
      manifest = Path.join(sdk.path, "AndroidManifest.xml")
      build_package_R(project, manifest)
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

  defp build_package_R(project, manifest_path) do
    cmdline = [
      project.aapt,
      "package", "-m",
      "--auto-add-overlay",
      "-J", project.apk_gen_dir,
      "-M", manifest_path,
      "-I", project.base_package, 
      "-S", project.apk_res_dir
    ]
    cmdline = cmdline ++ :lists.join("-S", aapt_all(project, "res"))
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
    cmdline = [
      project.dx,
      "--dex",
      "--output", Path.join(project.apk_bin_dir, "classes.dex"),
      Path.join(project.apk_bin_dir, "classes.jar")
    ]
    run_cmd(project, cmdline)
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
      "-A", project.apk_asserts_dir
    ]
    cmdline = cmdline ++ :lists.join("-S", aapt_all(project, "res"))
    cmdline = cmdline ++ :lists.join("-A", aapt_all(project, "assets"))
    
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
    replace_dir(project.apk_asserts_dir, Path.join(resources_out, "asserts"))
    project
  end

  defp build_apk(project) do
    smali_dir = Path.join(project.apk_dir, "smali")
    dex_dir = Path.join(project.apk_bin_dir, "classes.dex")
    cmdline = [
      project.java, "-jar",
      project.baksmali,
      "-o", smali_dir, dex_dir
    ]

    run_cmd(project, cmdline)
    
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
    cmdline = [
      project.jarsigner,
      "-digestalg", "SHA1",
      "-sigalg", "MD5withRSA",
      "-verbose",
      "-keystore", project.keystore,
      "-storepass", project.storepass,
      "-keypass", project.keypass,
      "-signedjar", project.apk_signed_path,
      project.apk_unsigned_path, project.alias,
    ]
    run_cmd(project, cmdline)
  end

  defp clean(project) do
    project
  end

  defp run_cmd(project, [cmd | args]) do
    {output, 0} = System.cmd(cmd, args)
    IO.puts output 
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
end
