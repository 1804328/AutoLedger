// 由 gen_icu_check.py 生成，别手改；改完正则重跑：python tools/ocr_probe/gen_icu_check.py
// 用第二个正则引擎（V8/ICU）复核 Swift 侧 NSRegularExpression 用到的模式。
// 语法非法不会让 xcodebuild 失败 —— try? 静默返回 nil，那一档就永远不命中，
// 线上只表现为「金额没识别出来」，查不到根因。
const P = {"unitPatterns": ["(?:[¥￥]|RMB|rmb|人民币)\\s*(\\d{1,3}(?:,\\d{3})+(?:[.,]\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?)", "(\\d{1,3}(?:,\\d{3})+(?:[.,]\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?)\\s*(?:元整|块钱|元|块|圆)", "(\\d+(?:\\.\\d+)?)\\s*(?:毛|角)"], "anchor": ["(?:实付款|实付|已付款|已付|付款金额|支付金额|扣款金额|扣款|扣费|合计|总计|金额|支出|消费|支付)[:：]?\\s*[-－]?[¥￥]?\\s*([\\d,]+(?:\\.\\d{1,2})?)"], "chinese": ["([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟]+)\\s*(?:元整|块钱|元|块|圆)"], "plain": ["(?<![\\d.,])(\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?|\\d+(?:\\.\\d{1,2})?)(?![\\d.])"], "chineseBare": ["([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟点點]+)"], "noise": ["\\d{4}[-/年]\\d{1,2}[-/月]\\d{1,2}\\s*[日号]?", "\\d{1,2}\\s*月\\s*\\d{1,2}\\s*[日号]", "\\d{1,2}:\\d{2}(?::\\d{2})?", "\\d+\\s*天前", "(?:周|星期|礼拜)[一二三四五六日天]", "\\d{1,2}\\s*[日号]", "(?<![\\d月.])\\d{1,2}\\s*月", "\\d{4,}年", "\\d{8,}", "\\d+\\*+\\d+"], "noteMoneyResiduals": ["\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?", "\\d+\\.\\d{1,2}"]};

let bad = 0;
for (const [k, arr] of Object.entries(P)) {
  for (const p of arr) {
    try { new RegExp(p); } catch (e) { bad++; console.log('SYNTAX-FAIL', k, p, e.message); }
  }
}
console.log(bad ? `${bad} 条模式语法非法` : `全部 ${Object.values(P).flat().length} 条模式在 V8 下语法合法`);

for (const [key, idx, input, want] of [["unitPatterns", 0, "¥5,099.00", "5,099.00"], ["unitPatterns", 1, "1,286.50元", "1,286.50"], ["plain", 0, "1,286.50", "1,286.50"], ["plain", 0, "余额 286 元", "286"], ["noise", 9, "6214****8888", "6214****8888"]]) {
  const m = new RegExp(P[key][idx]).exec(input);
  const got = m ? (m[1] !== undefined ? m[1] : m[0]) : null;
  console.log((got === want ? 'OK   ' : 'DIFF ') + JSON.stringify(input)
    + ` -> ${JSON.stringify(got)} (期望 ${JSON.stringify(want)})`);
}
