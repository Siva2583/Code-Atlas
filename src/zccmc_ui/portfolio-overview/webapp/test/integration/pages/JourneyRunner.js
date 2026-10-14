sap.ui.define([
    "sap/fe/test/JourneyRunner",
	"portfoliooverview/test/integration/pages/PortfolioItemsList.gen",
	"portfoliooverview/test/integration/pages/PortfolioItemsObjectPage.gen"
], function (JourneyRunner, PortfolioItemsListGenerated, PortfolioItemsObjectPageGenerated) {
    'use strict';

    const runner = new JourneyRunner({
        launchUrl: sap.ui.require.toUrl('portfoliooverview') + '/test/flp.html#app-preview',
        pages: {
			onThePortfolioItemsListGenerated: PortfolioItemsListGenerated,
			onThePortfolioItemsObjectPageGenerated: PortfolioItemsObjectPageGenerated
        },
        async: true
    });

    return runner;
});

