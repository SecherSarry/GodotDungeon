extends RefCounted
class_name HeroAction

# 英雄的"待办动作"：输入路径只负责造一个塞进 hero.cur_action，真正的执行在 Hero.act() 里分派。
# 直译 SPD Hero.java 的内层接口 `HeroAction` 及其实现类，但只保留本工程有对应物的几个——
# Alchemy / Mine / Buy / OpenChest / Interact / Unlock 六个本工程没有对应机制
# （上锁门已在 Char.walk_to 里内联解锁），不建空壳。
#
# extends RefCounted 而非 Node：这些是纯数据小对象，new 出来即用即弃、不进场景树。
# Node 不是引用计数对象，new 了不 add_child 也不 free 就是永久泄漏（同 Buff.detach 注释里那条）。

# 目标格。Move / PickUp / LvlTransition 用它；Attack 用 target。
var dst: Vector2i

class Move extends HeroAction:
	pass

class Attack extends HeroAction:
	# 不注解 Char：Char 的方法签名里引用了 HeroAction，本类若再静态引用 Char 就构成
	# 循环依赖（同 Mob.gd:37 / Buff.gd 顶部那条）。这里本就是鸭子类型，无需静态类型。
	var target = null

class PickUp extends HeroAction:
	pass

# 出入口。与 Move 分开是因为触发时机不同：走到那一格之后要再花一拍才下楼（见 Hero.act_transition）。
class LvlTransition extends HeroAction:
	pass
