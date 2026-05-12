const { withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

function ensureYogaFlagInPodfile(podfileContents) {
  const marker = "__apply_Xcode_12_5_M1_post_install_workaround(installer)";
  if (!podfileContents.includes(marker)) {
    return podfileContents;
  }

  const injection = `

    installer.pods_project.targets.each do |t|
      if t.name == 'Yoga' || t.name.start_with?('Yoga-')
        t.build_configurations.each do |bc|
          bc.build_settings['OTHER_CPLUSPLUSFLAGS'] ||= '$(inherited)'
          bc.build_settings['OTHER_CPLUSPLUSFLAGS'] += ' -Wno-deprecated-literal-operator'
        end
      end
    end
`;

  if (podfileContents.includes('Wno-deprecated-literal-operator')) {
    return podfileContents;
  }

  return podfileContents.replace(marker, marker + injection);
}

module.exports = function withYogaWarningWorkaround(config) {
  return withDangerousMod(config, [
    'ios',
    async (config) => {
      const podfilePath = path.join(config.modRequest.platformProjectRoot, 'Podfile');
      const contents = fs.readFileSync(podfilePath, 'utf8');
      const next = ensureYogaFlagInPodfile(contents);
      if (next !== contents) {
        fs.writeFileSync(podfilePath, next);
      }
      return config;
    },
  ]);
};
