extends Resource
class_name Bundlable

# 可序列化对象的统一契约。Item 与 Actor 两条数据线都继承它，
# 于是"能存档"有个共同的类型可依赖，而不是各自散着实现一对同名方法。
# 统一拼写 deserialize（此前误写成 deseriralize）。
func serialize() -> Dictionary:
	return {}

func deserialize(data: Dictionary) -> void:
	pass

# ---------- 序列化共用工具（供 Item / Buff 这类"字段平铺"的对象复用） ----------
# 属性遍历与 Item.copy（Item.gd:153-158）同源，且只收 int/float/bool/String：
# icon 之类的 Resource 值进不了 JSON，也不该进（还原时由脚本自己重建）。
# 注意：JSON 的对象键只能是字符串、数字读回来一律是 float，故写出去时是原样，
# 读回来由 apply_props 按当前字段类型归一，别在别处再手写一遍转换。
static func script_props(obj: Object, skip: Array = []) -> Dictionary:
	var out := {}
	for prop in obj.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.name in skip:
			continue
		var v = obj.get(prop.name)
		if v is int or v is float or v is bool or v is String:
			out[prop.name] = v
	return out

# 把 script_props 收出来的字典逐键写回。只写对象自身声明的脚本属性，
# 字段类型是 int 而读回来是 float 的一律 int() 归一（JSON 数字只解析成 float）。
static func apply_props(obj: Object, props: Dictionary) -> void:
	var writable := {}
	for prop in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			writable[prop.name] = true
	for key in props:
		if not writable.has(key):
			continue
		var v = props[key]
		if obj.get(key) is int and v is float:
			v = int(v)
		obj.set(key, v)
