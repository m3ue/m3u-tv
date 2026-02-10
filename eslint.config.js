module.exports = [
  {
    ignores: [
      '**/node_modules/**',
      '**/android/**',
      '**/ios/**',
      '**/.expo/**',
      'planby-native-pro-main/**',
    ],
  },
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: require('@typescript-eslint/parser'),
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    rules: {
      semi: ['error', 'always'],
      'no-unused-vars': 'warn',
      'react/jsx-uses-react': 'error',
      'react/jsx-uses-vars': 'error',
    },
    plugins: {
      react: require('eslint-plugin-react'),
    },
  },
];
