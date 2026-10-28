const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        // Base components not stubbed by @salesforce/sfdx-lwc-jest yet.
        '^lightning/modal$': '<rootDir>/jest-mocks/lightning/modal',
        '^lightning/modalHeader$': '<rootDir>/jest-mocks/lightning/modalHeader/modalHeader',
        '^lightning/modalBody$': '<rootDir>/jest-mocks/lightning/modalBody/modalBody',
        '^lightning/modalFooter$': '<rootDir>/jest-mocks/lightning/modalFooter/modalFooter'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    testPathIgnorePatterns: ['<rootDir>/node_modules/']
};
