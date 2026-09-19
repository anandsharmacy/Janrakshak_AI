<?xml version="1.0" encoding="UTF-8"?>
<!-- Flood / landslide susceptibility zones. Colours match the app palette
     (saffron600 = caution/flood, signalRed700 = landslide). -->
<StyledLayerDescriptor version="1.0.0"
    xmlns="http://www.opengis.net/sld" xmlns:ogc="http://www.opengis.net/ogc"
    xmlns:xlink="http://www.w3.org/1999/xlink"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.0.0/StyledLayerDescriptor.xsd">
  <NamedLayer>
    <Name>ner_risk_zones</Name>
    <UserStyle>
      <Title>NER risk zones</Title>
      <FeatureTypeStyle>
        <Rule>
          <Title>Flood susceptibility</Title>
          <ogc:Filter><ogc:PropertyIsEqualTo><ogc:PropertyName>kind</ogc:PropertyName><ogc:Literal>flood</ogc:Literal></ogc:PropertyIsEqualTo></ogc:Filter>
          <PolygonSymbolizer>
            <Fill><CssParameter name="fill">#D97A1F</CssParameter><CssParameter name="fill-opacity">0.28</CssParameter></Fill>
            <Stroke><CssParameter name="stroke">#D97A1F</CssParameter><CssParameter name="stroke-width">1.5</CssParameter></Stroke>
          </PolygonSymbolizer>
        </Rule>
        <Rule>
          <Title>Landslide susceptibility</Title>
          <ogc:Filter><ogc:PropertyIsEqualTo><ogc:PropertyName>kind</ogc:PropertyName><ogc:Literal>landslide</ogc:Literal></ogc:PropertyIsEqualTo></ogc:Filter>
          <PolygonSymbolizer>
            <Fill><CssParameter name="fill">#B3261E</CssParameter><CssParameter name="fill-opacity">0.25</CssParameter></Fill>
            <Stroke><CssParameter name="stroke">#B3261E</CssParameter><CssParameter name="stroke-width">1.5</CssParameter><CssParameter name="stroke-dasharray">6 4</CssParameter></Stroke>
          </PolygonSymbolizer>
        </Rule>
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
