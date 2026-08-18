// Explicit Babel config so Drizzle's .sql migrations can be inlined as strings.
// babel-preset-expo (pinned to the SDK version expo already uses) is the same
// preset Metro applied implicitly before; the inline-import plugin is additive.
module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    // `react-native-worklets/plugin` (Reanimated 4's worklet transform) MUST be
    // last in the plugins list.
    plugins: [['inline-import', { extensions: ['.sql'] }], 'react-native-worklets/plugin'],
  };
};
