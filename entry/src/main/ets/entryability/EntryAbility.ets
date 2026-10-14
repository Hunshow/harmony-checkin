import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../utils/Logger';

/**
 * 应用入口 Ability
 * ------------------------------------------------------------------
 * 重点处理 PC（2in1）场景：默认按窗口尺寸自适应，最小窗口尺寸设得足够大，
 * 避免用户把窗口拖到极小导致表格不可用。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 强制浅色模式，保证与设计令牌一致（本 demo 只提供浅色主题）
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    Logger.info('Ability onCreate');
  }

  onDestroy(): void {
    Logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code !== 0) {
        Logger.error(`加载页面失败：${JSON.stringify(err)}`);
        return;
      }
      Logger.info('页面加载成功');

      // PC 端设置最小窗口尺寸，防止布局被压坏
      windowStage.getMainWindow().then((win: window.Window) => {
        try {
          win.setWindowLimits({ minWidth: 480, minHeight: 600 });
        } catch (e) {
          Logger.warn(`设置窗口最小尺寸失败：${(e as BusinessError).message}`);
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    Logger.info('WindowStage 销毁');
  }

  onForeground(): void {
    Logger.info('Ability onForeground');
  }

  onBackground(): void {
    Logger.info('Ability onBackground');
  }
}
