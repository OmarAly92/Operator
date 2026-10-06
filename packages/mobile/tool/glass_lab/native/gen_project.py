import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE / "GlassLab.xcodeproj"


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


APP = oid("target.app")
DRIVER = oid("target.driver")
ROOT = oid("project")
MAIN = oid("group.main")
PRODUCTS = oid("group.products")
APP_DIR = oid("sync.app")
DRIVER_DIR = oid("sync.driver")
APP_PRODUCT = oid("product.app")
DRIVER_PRODUCT = oid("product.driver")
PROXY = oid("proxy.app")
DEPENDENCY = oid("dependency.app")


def phase(kind, name):
    return oid(f"phase.{kind}.{name}")


def config(name, kind):
    return oid(f"config.{name}.{kind}")


def config_list(name):
    return oid(f"configlist.{name}")


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Manual",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
RELEASE = {
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}
APP_SETTINGS = {
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.operator.glasslab",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
}
DRIVER_SETTINGS = {
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.operator.glasslab.driver",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "TEST_TARGET_NAME": "GlassLab",
}


def settings_block(values, indent):
    pad = "\t" * indent
    return "\n".join(f"{pad}{k} = {v};" for k, v in sorted(values.items()))


def build_configuration(ident, name, values):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{settings_block(values, 4)}\n\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};\n"
    )


def configuration_list(ident, debug, release):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n\t\t\t\t{debug},\n\t\t\t\t{release},\n\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};\n"
    )


def empty_phase(ident, isa):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )


def native_target(ident, name, group, product, product_type, dependencies):
    deps = "".join(f"\t\t\t\t{d},\n" for d in dependencies)
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {config_list(name)};\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{phase('sources', name)},\n"
        f"\t\t\t\t{phase('frameworks', name)},\n"
        f"\t\t\t\t{phase('resources', name)},\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n\t\t\t);\n"
        f"\t\t\tdependencies = (\n{deps}\t\t\t);\n"
        f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{group},\n\t\t\t);\n"
        f"\t\t\tname = {name};\n"
        f"\t\t\tpackageProductDependencies = (\n\t\t\t);\n"
        f"\t\t\tproductName = {name};\n"
        f"\t\t\tproductReference = {product};\n"
        f'\t\t\tproductType = "{product_type}";\n'
        f"\t\t}};\n"
    )


def pbxproj():
    objects = []
    objects.append(
        f"\t\t{PROXY} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {ROOT};\n"
        f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {APP};\n\t\t\tremoteInfo = GlassLab;\n\t\t}};\n"
    )
    objects.append(
        f"\t\t{APP_PRODUCT} = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = GlassLab.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )
    objects.append(
        f"\t\t{DRIVER_PRODUCT} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
        f"includeInIndex = 0; path = GlassLabDriver.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )
    for ident, path in ((APP_DIR, "GlassLab"), (DRIVER_DIR, "GlassLabDriver")):
        objects.append(
            f"\t\t{ident} = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
            f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
        )
    for name in ("GlassLab", "GlassLabDriver"):
        objects.append(empty_phase(phase("frameworks", name), "PBXFrameworksBuildPhase"))
        objects.append(empty_phase(phase("resources", name), "PBXResourcesBuildPhase"))
        objects.append(empty_phase(phase("sources", name), "PBXSourcesBuildPhase"))
    objects.append(
        f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_DIR},\n"
        f"\t\t\t\t{DRIVER_DIR},\n\t\t\t\t{PRODUCTS},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
    )
    objects.append(
        f"\t\t{PRODUCTS} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_PRODUCT},\n"
        f"\t\t\t\t{DRIVER_PRODUCT},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
    )
    objects.append(
        native_target(APP, "GlassLab", APP_DIR, APP_PRODUCT, "com.apple.product-type.application", [])
    )
    objects.append(
        native_target(
            DRIVER,
            "GlassLabDriver",
            DRIVER_DIR,
            DRIVER_PRODUCT,
            "com.apple.product-type.bundle.ui-testing",
            [DEPENDENCY],
        )
    )
    objects.append(
        f"\t\t{ROOT} = {{\n"
        f"\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n"
        f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 2700;\n"
        f"\t\t\t\tLastUpgradeCheck = 2700;\n"
        f"\t\t\t\tTargetAttributes = {{\n"
        f"\t\t\t\t\t{APP} = {{\n\t\t\t\t\t\tCreatedWithXcodeVersion = 27.0;\n\t\t\t\t\t}};\n"
        f"\t\t\t\t\t{DRIVER} = {{\n\t\t\t\t\t\tCreatedWithXcodeVersion = 27.0;\n"
        f"\t\t\t\t\t\tTestTargetID = {APP};\n\t\t\t\t\t}};\n"
        f"\t\t\t\t}};\n"
        f"\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {config_list('project')};\n"
        f"\t\t\tdevelopmentRegion = en;\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {MAIN};\n"
        f"\t\t\tminimizedProjectReferenceProxies = 1;\n"
        f"\t\t\tpreferredProjectObjectVersion = 77;\n"
        f"\t\t\tproductRefGroup = {PRODUCTS};\n"
        f'\t\t\tprojectDirPath = "";\n'
        f'\t\t\tprojectRoot = "";\n'
        f"\t\t\ttargets = (\n\t\t\t\t{APP},\n\t\t\t\t{DRIVER},\n\t\t\t);\n"
        f"\t\t}};\n"
    )
    objects.append(
        f"\t\t{DEPENDENCY} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {APP};\n"
        f"\t\t\ttargetProxy = {PROXY};\n\t\t}};\n"
    )
    for name, extra in (("project", {}), ("GlassLab", APP_SETTINGS), ("GlassLabDriver", DRIVER_SETTINGS)):
        base = COMMON if name == "project" else {}
        objects.append(build_configuration(config(name, "debug"), "Debug", {**base, **(DEBUG if name == "project" else {}), **extra}))
        objects.append(build_configuration(config(name, "release"), "Release", {**base, **(RELEASE if name == "project" else {}), **extra}))
        objects.append(configuration_list(config_list(name), config(name, "debug"), config(name, "release")))
    body = "".join(objects)
    return (
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n"
        f"\tobjects = {{\n{body}\t}};\n\trootObject = {ROOT};\n}}\n"
    )


def buildable(ident, product, name):
    return (
        f'            <BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{ident}"\n'
        f'               BuildableName = "{product}"\n'
        f'               BlueprintName = "{name}"\n'
        f'               ReferencedContainer = "container:GlassLab.xcodeproj">\n'
        f'            </BuildableReference>\n'
    )


def scheme():
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Scheme LastUpgradeVersion = "2700" version = "1.7">\n'
        '   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">\n'
        '      <BuildActionEntries>\n'
        '         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">\n'
        + buildable(APP, "GlassLab.app", "GlassLab")
        + '         </BuildActionEntry>\n'
        '      </BuildActionEntries>\n'
        '   </BuildAction>\n'
        '   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv = "YES">\n'
        '      <Testables>\n'
        '         <TestableReference skipped = "NO">\n'
        + buildable(DRIVER, "GlassLabDriver.xctest", "GlassLabDriver")
        + '         </TestableReference>\n'
        '      </Testables>\n'
        '   </TestAction>\n'
        '   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">\n'
        '      <BuildableProductRunnable runnableDebuggingMode = "0">\n'
        + buildable(APP, "GlassLab.app", "GlassLab")
        + '      </BuildableProductRunnable>\n'
        '   </LaunchAction>\n'
        '</Scheme>\n'
    )


def main(project=PROJECT):
    project = Path(project)
    (project / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (project / "project.pbxproj").write_text(pbxproj())
    (project / "xcshareddata" / "xcschemes" / "GlassLab.xcscheme").write_text(scheme())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else PROJECT)
