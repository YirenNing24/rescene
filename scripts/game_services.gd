class_name GameServices
extends RefCounted
## Typed access to autoloads, including scripts compiled before the scene tree
## has instantiated them (standalone regression tools and export scripts).

static func session() -> ResceneAuthSession:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("AuthSession") as ResceneAuthSession

static func progression() -> ProgressionService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("Progression") as ProgressionService

static func scores() -> CloudScoresService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("CloudScores") as CloudScoresService

static func commerce() -> CommerceService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("Commerce") as CommerceService

static func photos() -> ProfileMediaService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("ProfileMedia") as ProfileMediaService

static func social() -> SocialService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node("Social") as SocialService
