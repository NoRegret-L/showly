import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { traktAuth } from '../data/TraktAuth';
import { memoryEvents } from '../model/CacheLifecycle';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.uri) {
      traktAuth.receive(want.uri);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.uri) {
      traktAuth.receive(want.uri);
    }
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void { memoryEvents.notify(); }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'ShowlyPreview', 'Page load failed: %{public}d', err.code);
      }
    });
  }
}
