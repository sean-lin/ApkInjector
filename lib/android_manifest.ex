defmodule Injector.AndroidManifest do
  defstruct [
    package: nil,
    main_activity_name: nil,
    main_activity_intent_filter: nil,
    body: nil,
    uses_permission: nil
  ]
 
  @scan_opt [quiet: true]

  require Record
  for {name, define} <- Record.extract_all(from_lib: "xmerl/include/xmerl.hrl") do
    Record.defrecord name, define
  end

  def file(file) when is_binary(file) do
    {doc, _} = String.to_charlist(file) 
                |> :xmerl_scan.file(@scan_opt)
    init(doc)
  end

  def string(data) when is_binary(data) do
    data
    |> :erlang.binary_to_list
    |> string
  end
  def string(data) when is_list(data) do
    {doc, _} = :xmerl_scan.string(data, @scan_opt)
    init(doc)
  end
  
  def merge(target, from) do
    uses_permission = :sets.union(target.uses_permission, from.uses_permission)
    {[target_app], target_manifest} = partition_element(target.body, :application)
    {[from_app], from_manifest} = partition_element(from.body, :application)
    
    target_app = merge_element(target_app, from_app)
    target_manifest = xmlElement(content: target_content) = merge_element(target_manifest, from_manifest)
    
    new_root = xmlElement(target_manifest, content: [target_app|target_content])
    target = %{target | body: new_root, uses_permission: uses_permission}
    
    case from.main_activity_name do
      nil -> target
      name ->
        %{target| main_activity_name: name, main_activity_intent_filter: from.main_activity_intent_filter}
    end
  end
 
  def render(manifest) do
    xml_prolog = ~s(<?xml version="1.0" encoding="utf-8" standalone="no"?>)
    permissions = gen_uses_permission(:sets.to_list(manifest.uses_permission))
    
    main_activity_name = manifest.main_activity_name
    root = insert_element(manifest.body, permissions)
    |> change_element(:application, fn app ->
      change_element(app, :activity, fn n ->
        case get_android_name(n) do
          ^main_activity_name -> insert_element(n, [manifest.main_activity_intent_filter])
          _o -> n
        end
      end)
    end)
    |> change_attribute(:package, fn _x -> manifest.package end)
    
    :xmerl.export_simple([root], :xmerl_xml, prolog: xml_prolog)
  end

  defp init(doc) do
    manifest = %Injector.AndroidManifest{}

    [root] = :xmerl_xpath.string('/manifest[1]', doc)
    
    manifest
    |> Map.put(:body, root)
    |> Map.put(:package, get_attribute(root, :package))
    |> get_uses_permission
    |> get_main_activity
  end

  def get_attribute(xmlElement(attributes: attributes), attribute) do
    xmlAttribute(value: value) = List.keyfind(attributes, attribute, xmlAttribute(:name))
    value
  end

  defp get_main_activity(manifest) do
    root = manifest.body
    xpath = 'application[1]/activity/intent-filter/action[@android:name=\'android.intent.action.MAIN\']/../..' 
    case :xmerl_xpath.string(xpath, root) do
      [] -> manifest
      [activity] ->
        {activity, intent_filter} = drop_intent_filter(activity)
        main_activity_name = get_android_name(activity) 
        root = change_element(root, :application, fn app ->
          change_element(app, :activity, fn n ->
            case get_android_name(n) do
              ^main_activity_name -> activity
              _o -> n
            end
          end)
        end)
        %{manifest| body: root,
          main_activity_name: main_activity_name, 
          main_activity_intent_filter: intent_filter}
    end
  end
  
  defp get_uses_permission(manifest) do
    root = manifest.body
    uses_permission = :xmerl_xpath.string('uses-permission/@android:name', root)
                      |> Enum.reduce(:sets.new(), fn xmlAttribute(value: value), acc -> 
                        :sets.add_element(value, acc)
                      end)

    root = change_element(root, :"uses-permission", fn _x -> nil end)

    %{manifest| body: root, uses_permission: uses_permission}
  end

  defp drop_intent_filter(activity) do
    xpath = 'intent-filter/action[@android:name=\'android.intent.action.MAIN\']/..' 
    [intent_filter] = :xmerl_xpath.string(xpath, activity)
    content = xmlElement(activity, :content) |> Enum.filter(
      fn ^intent_filter -> false
        _ -> true
    end)
    {xmlElement(activity, content: content), intent_filter}
  end

  # 返回新元素修改， 返回非tuple删除
  def change_element(xmlElement(content: content)=root, name, cb) do
    content = content |> Enum.map(
      fn xmlElement(name: ^name)=match -> cb.(match)
        any -> any
      end) |> Enum.filter(fn x -> is_tuple(x) end)
    xmlElement(root, content: content)
  end
  
  def change_attribute(xmlElement(attributes: attributes)=root, name, cb) do
    attributes = attributes |> Enum.map(
      fn xmlAttribute(name: ^name)=match ->
        case cb.(match) do
          xmlAttribute()=attr -> attr
          value when is_list(value) -> xmlAttribute(match, value: value)
          o -> o
        end
        any -> any
      end) |> Enum.filter(fn x -> is_tuple(x) end)
    xmlElement(root, attributes: attributes)
  end
  
  # 取出指定的元素
  defp partition_element(xmlElement(content: content)=root, name) do
    {take, rest} = Enum.partition(content, 
     fn xmlElement(name: ^name) -> true
     _ -> false
    end)
    {take, xmlElement(root, content: rest)}
  end
  
  defp merge_element(target, xmlElement(content: from)) do
    insert_element(target, from)
  end

  defp insert_element(xmlElement(content: content)=target, from_content) do
    xmlElement(target, content: content ++ from_content)
  end

  defp get_android_name(element) do
    get_attribute(element, :"android:name")
  end

  defp gen_uses_permission(permissions) do
    for permission <- permissions do
      attrib = xmlAttribute(name: :"android:name", value: permission)
      xmlElement(name: :"uses-permission", attributes: [attrib])
    end
  end

  def xml_inspect(root) do
    xml_prolog = ~s(<?xml version="1.0" encoding="utf-8" standalone="no"?>)
    :xmerl.export_simple([root], :xmerl_xml, prolog: xml_prolog)
    |> IO.puts
  end
end
