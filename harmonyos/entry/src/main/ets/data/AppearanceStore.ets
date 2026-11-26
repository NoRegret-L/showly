import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

export class AppearanceStore {
  private store: preferences.Preferences;
  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferencesSync(context, { name: 'showly_appearance' });
  }
  load(): string {
    const value = this.store.getSync('theme', 'system');
    return value === 'dark' || value === 'light' ? value : 'system';
  }
  async save(value: string): Promise<void> {
    await this.store.put('theme', value);
    await this.store.flush();
  }
}

export function applyAppearance(context: common.UIAbilityContext, mode: string): void {
  context.getApplicationContext().setColorMode(mode === 'dark' ?
    ConfigurationConstant.ColorMode.COLOR_MODE_DARK : mode === 'light' ?
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
}
