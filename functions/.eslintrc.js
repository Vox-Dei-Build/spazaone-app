module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    // By extending from a plugin config, we can get recommended rules without having to add them manually.
    "plugin:prettier/recommended",
    "eslint:recommended",
    "plugin:import/recommended",
    "plugin:@typescript-eslint/recommended",
    "google",
    // This disables the formatting rules in ESLint that Prettier is going to be responsible for handling.
    // Make sure it's always the last config, so it gets the chance to override other configs.
    "eslint-config-prettier",
  ],
  rules: {
    // Add your own rules here to override ones from the extended configs.
    "prettier/prettier": "warn", // This will show prettier formatting errors as ESLint errors
    "linebreak-style": 0,
    "import/no-unresolved": 0,
    // Disable JSDoc validation coming from the Google config
    "valid-jsdoc": "off",
    // Optionally disable requiring JSDoc presence as well
    "require-jsdoc": "off",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
  ],
  plugins: ["@typescript-eslint", "import", "prettier"],
};
