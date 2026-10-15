import opaTest from "sap/ui/test/opaQunit";
import type { Given, When, Then } from "./types/OpaJourneyTypes.gen";
import runner from "./pages/JourneyRunner";

function journey() {
    QUnit.module("First journey");

    opaTest("Start application", function (Given: Given, _When: When, Then: Then) {
        Given.iStartMyApp();
        Then.onTheRulesListGenerated.iSeeThisPage();
    });


    opaTest("Navigate to ObjectPage", function (_Given: Given, When: When, Then: Then) {
        // Note: this test will fail if the ListReport page doesn't show any data
        
        When.onTheRulesListGenerated.onFilterBar().iExecuteSearch();
        
        Then.onTheRulesListGenerated.onTable("").iCheckRows();

        When.onTheRulesListGenerated.onTable("").iPressRow(0);
        Then.onTheRulesObjectPageGenerated.iSeeThisPage();

    });

    opaTest("Teardown", function (Given: Given) {
        // Cleanup
        Given.iTearDownMyApp();
    });
}

runner.run([journey]);
