const wmf = {}

wmf.editButtons = require('./js/transforms/addEditButtons')
wmf.compatibility = require('wikimedia-page-library').CompatibilityTransform
wmf.elementLocation = require('./js/elementLocation')
wmf.utilities = require('./js/utilities')
wmf.findInPage = require('./js/findInPage')
wmf.footerReadMore = require('wikimedia-page-library').FooterReadMore
wmf.footerMenu = require('wikimedia-page-library').FooterMenu
wmf.footerLegal = require('wikimedia-page-library').FooterLegal
wmf.footerContainer = require('wikimedia-page-library').FooterContainer
wmf.imageDimming = require('wikimedia-page-library').DimImagesTransform
wmf.tables = require('./js/transforms/collapseTables')
wmf.themes = require('wikimedia-page-library').ThemeTransform
wmf.redLinks = require('wikimedia-page-library').RedLinks
wmf.paragraphs = require('./js/transforms/relocateFirstParagraph')
wmf.images = require('./js/transforms/widenImages')
wmf.platform = require('wikimedia-page-library').PlatformTransform

window.wmf = wmf