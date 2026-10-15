import JourneyRunner from "sap/fe/test/JourneyRunner";
import ListReport from "sap/fe/test/ListReport";
import ObjectPage from "sap/fe/test/ObjectPage";
import CustomRulesListGenerated from "./RulesList.gen";
import CustomRulesObjectPageGenerated from "./RulesObjectPage.gen";

const runner = new JourneyRunner({
    launchUrl: sap.ui.require.toUrl("rulesadmin") + "/test/flp.html#app-preview",
    pages: {
        onTheRulesListGenerated: new ListReport(
            {
                appId: "rulesadmin",
                componentId: "RulesList",
                entitySet: "",
                contextPath: "/Rules"
            },
            CustomRulesListGenerated
        ),
        onTheRulesObjectPageGenerated: new ObjectPage(
            {
                appId: "rulesadmin",
                componentId: "RulesObjectPage",
                entitySet: "",
                contextPath: "/Rules"
            },
            CustomRulesObjectPageGenerated
        )
    },
    async: true
});

export default runner;
