use argus_domain::{AppearanceSettings, ThemeMode};

#[test]
fn theme_mode_accepts_only_the_three_canonical_values() {
    assert_eq!(ThemeMode::parse("system"), Ok(ThemeMode::System));
    assert_eq!(ThemeMode::parse("light"), Ok(ThemeMode::Light));
    assert_eq!(ThemeMode::parse("dark"), Ok(ThemeMode::Dark));
    assert!(ThemeMode::parse("System").is_err());
    assert!(ThemeMode::parse("1").is_err());
    assert!(ThemeMode::parse("default").is_err());
    assert_eq!(ThemeMode::System.as_str(), "system");
    assert_eq!(ThemeMode::Light.as_str(), "light");
    assert_eq!(ThemeMode::Dark.as_str(), "dark");
}

#[test]
fn appearance_settings_equality_depends_only_on_theme_mode() {
    assert_eq!(
        AppearanceSettings::new(ThemeMode::System),
        AppearanceSettings::new(ThemeMode::System)
    );
    assert_ne!(
        AppearanceSettings::new(ThemeMode::System),
        AppearanceSettings::new(ThemeMode::Dark)
    );
}
