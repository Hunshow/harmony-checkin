import { AppData } from '../viewmodel/AppData';

/**
 * 全局状态
 * ------------------------------------------------------------------
 * 极简 Observable：@Observed 修饰 AppData，配合 @ObjectLink 让子组件也能响应变更。
 * demo 规模下不需要引入第三方状态库，减少依赖便于开源传播。
 */
@Observed
export class AppStore {
  /** 业务数据与派生结果 */
  data: AppData = new AppData();
}

/** 进程内单例（页面通过 aboutToAppear 注入，避免全局变量散落） */
export const appStore: AppStore = new AppStore();
