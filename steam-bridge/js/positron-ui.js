/**
 * Positron Runtime Steam UI Injector
 *
 * Hooks the unminified SteamClient bridge, MobX stores (appDetailsStore, settingsStore),
 * and React Fiber tree at runtime instead of regex-patching minified Webpack JSX bundles.
 */
(function installPositronUI() {
  if (globalThis.__POSITRON_UI_ACTIVE__) return;
  globalThis.__POSITRON_UI_ACTIVE__ = true;

  const POSITRON_CONFIG = globalThis.__POSITRON_CONFIG__ || {
    defaultTool: "positron-proton-default",
    tools: []
  };

  function patchMobXStores() {
    const settingsStore = globalThis.settingsStore;
    if (settingsStore && settingsStore.settings) {
      try {
        settingsStore.settings.bCompatEnabled = true;
        if (!settingsStore.settings.strCompatTool) {
          settingsStore.settings.strCompatTool = POSITRON_CONFIG.defaultTool;
        }
      } catch (_) {}
    }

    const appStore = globalThis.appStore;
    if (appStore && appStore.allApps && appStore.allApps.length > 0) {
      try {
        const proto = Object.getPrototypeOf(appStore.allApps[0]);
        if (proto && !proto.__positronPatchedInvalidOS) {
          const origDesc = Object.getOwnPropertyDescriptor(proto, "is_invalid_os_type");
          Object.defineProperty(proto, "is_invalid_os_type", {
            configurable: true,
            get() { return false; },
            set: origDesc && origDesc.set ? origDesc.set : undefined
          });
          proto.__positronPatchedInvalidOS = true;
        }
      } catch (_) {}
    }
  }

  function wrapSteamClientApps() {
    const apps = globalThis.SteamClient && globalThis.SteamClient.Apps;
    if (!apps || apps.__positronWrapped) return;
    apps.__positronWrapped = true;

    if (typeof apps.GetAvailableCompatTools === "function") {
      const origGetTools = apps.GetAvailableCompatTools.bind(apps);
      apps.GetAvailableCompatTools = async function(appId) {
        const nativeList = (await origGetTools(appId).catch(() => [])) || [];
        if (nativeList.length > 0) return nativeList;
        return POSITRON_CONFIG.tools.map((t, idx) => ({
          strToolName: t.name,
          strDisplayName: t.display,
          bIsDefault: idx === 0
        }));
      };
    }

    if (typeof apps.SpecifyCompatTool === "function") {
      const origSpecify = apps.SpecifyCompatTool.bind(apps);
      apps.SpecifyCompatTool = function(appId, toolName) {
        globalThis.dispatchEvent(
          new CustomEvent("positron:tool-selected", {
            detail: { appId, toolName }
          })
        );
        return origSpecify(appId, toolName);
      };
    }
  }

  function findReactFiber(domNode) {
    if (!domNode) return null;
    const keys = Object.keys(domNode);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].startsWith("__reactFiber$") || keys[i].startsWith("__reactInternalInstance$")) {
        return domNode[keys[i]];
      }
    }
    return null;
  }

  globalThis.__POSITRON_BRIDGE__ = {
    version: "1.0.0",
    patchMobXStores,
    wrapSteamClientApps,
    findReactFiber
  };

  patchMobXStores();
  wrapSteamClientApps();
})();