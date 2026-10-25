import tseslint from 'typescript-eslint'

// Formatting is Prettier's job; ESLint only looks for likely bugs.
export default tseslint.config(
  { ignores: ['server/dist/**', '**/node_modules/**'] },

  {
    files: ['server/src/**/*.ts', 'server/build.mjs'],
    extends: [...tseslint.configs.recommended],
    rules: {
      curly: ['error', 'all'],
      'no-console': ['warn', { allow: ['error', 'warn'] }],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { varsIgnorePattern: '^_', argsIgnorePattern: '^_' },
      ],
    },
  },
)
