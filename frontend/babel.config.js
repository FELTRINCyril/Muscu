// Explicit Babel config so Drizzle's .sql migrations can be inlined as strings.
// babel-preset-expo (pinned to the SDK version expo already uses) is the same
// preset Metro applied implicitly before; the inline-import plugin is additive.
module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    // Note: babel-preset-expo auto-adds react-native-worklets/plugin (Reanimated
    // 4's worklet transform) when reanimated is installed — do NOT add it here
    // too, or worklets get transformed twice and crash at runtime.
    plugins: [['inline-import', { extensions: ['.sql'] }]],
  };
};
