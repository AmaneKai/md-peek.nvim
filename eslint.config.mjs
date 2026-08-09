import tseslint from 'typescript-eslint'
import stylistic from '@stylistic/eslint-plugin'
import unicorn from 'eslint-plugin-unicorn'
import importPlugin from 'eslint-plugin-import'

export default tseslint.config(
  {
    ignores: [
      'server/dist/**',
      'build/**',
      'server/node_modules/**',
      'node_modules/**',
      '*.config.js',
      '*.config.mjs',
      'src/components/ui/**',
      'src/features/scheduler/utils/**',
    ],
  },

  {
    files: ['server/src/**/*.{ts,js}', 'server/*.mjs'],

    extends: [...tseslint.configs.recommended],

    plugins: {
      '@stylistic': stylistic,
      unicorn,
      import: importPlugin,
    },

    rules: {
      /* --- 1. Formatting (auto-fixable — errors) --- */
      '@stylistic/semi': ['error', 'never'],
      '@stylistic/indent': ['error', 2],
      '@stylistic/quotes': ['error', 'single', { avoidEscape: true }],

      /* --- 2. Control Flow (auto-fixable — errors) --- */
      curly: ['error', 'all'],

      /* --- 3. Line length (not auto-fixable — warn only) --- */
      '@stylistic/max-len': ['warn', { code: 100, ignoreUrls: true }],

      /* --- 4. Naming (not auto-fixable — warn only) --- */
      'max-depth': ['error', 4],
      'id-length': [
        'warn',
        {
          min: 2,
          exceptions: [
            '_',
            'a',
            'b',
            'c',
            'd',
            'e',
            'f',
            'g',
            'h',
            'i',
            'j',
            'k',
            'm',
            'n',
            'o',
            'p',
            'r',
            's',
            't',
            'v',
            'w',
            'x',
            'y',
            'M',
            'T',
            'W',
            'H',
            'F',
            'S',
          ],
        },
      ],

      'unicorn/prevent-abbreviations': [
        'warn',
        {
          checkFilenames: false,
          replacements: {
            props: false,
            ref: false,
            params: false,
            args: false,
            env: false,
            ext: false,
            dir: false,
            res: false,
            e: false,
          },
        },
      ],

      // Interface naming only — no types: ['number'] to avoid needing project:true
      '@typescript-eslint/naming-convention': [
        'warn',
        {
          selector: 'interface',
          format: ['PascalCase'],
          custom: { regex: '^I[A-Z]', match: false },
        },
      ],

      /* --- 5. Safety (warn — fix manually over time) --- */
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { varsIgnorePattern: '^_', argsIgnorePattern: '^_' },
      ],
      'no-console': ['warn', { allow: ['error', 'warn'] }],

      /* --- 6. Architecture (errors — enforced going forward) --- */
      'import/no-restricted-paths': [
        'error',
        {
          zones: [
            {
              target: './server/src',
              from: './server/src/**/helpers.ts',
              message: 'Standard 3.6: Do not use generic helper files.',
            },
          ],
        },
      ],
    },
  },
)
