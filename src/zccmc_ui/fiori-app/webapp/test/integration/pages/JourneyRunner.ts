import JourneyRunner from "sap/fe/test/JourneyRunner";
import TemplatePage from "sap/fe/test/TemplatePage";
import CustomCustomObjectsMainGenerated from "./CustomObjectsMain.gen";

const runner = new JourneyRunner({
    launchUrl: sap.ui.require.toUrl("fioriapp") + "/test/flp.html#app-preview",
    pages: {
        onTheCustomObjectsMainGenerated: new (TemplatePage as unknown as new (id: string, defs: object) => object)(
            "fioriapp::CustomObjectsMain",
            CustomCustomObjectsMainGenerated
        )
    },
    async: true
});

export default runner;
