<?xml version="1.0" encoding="UTF-8"?>
<!-- Incident density heatmap (rendering transformation vec:Heatmap).
     Requires the GeoServer WPS extension (enabled in docker-compose.yml).
     Critical incidents weigh 4x, high 3x, medium 2x, low 1x. -->
<StyledLayerDescriptor version="1.0.0"
    xmlns="http://www.opengis.net/sld" xmlns:ogc="http://www.opengis.net/ogc"
    xmlns:xlink="http://www.w3.org/1999/xlink"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.0.0/StyledLayerDescriptor.xsd">
  <NamedLayer>
    <Name>ner_incident_heatmap</Name>
    <UserStyle>
      <Title>Incident heatmap</Title>
      <FeatureTypeStyle>
        <Transformation>
          <ogc:Function name="vec:Heatmap">
            <ogc:Function name="parameter"><ogc:Literal>data</ogc:Literal></ogc:Function>
            <ogc:Function name="parameter">
              <ogc:Literal>weightAttr</ogc:Literal>
              <ogc:Literal>weight</ogc:Literal>
            </ogc:Function>
            <ogc:Function name="parameter"><ogc:Literal>radiusPixels</ogc:Literal>
              <ogc:Function name="env"><ogc:Literal>radius</ogc:Literal><ogc:Literal>40</ogc:Literal></ogc:Function>
            </ogc:Function>
            <ogc:Function name="parameter"><ogc:Literal>pixelsPerCell</ogc:Literal><ogc:Literal>6</ogc:Literal></ogc:Function>
            <ogc:Function name="parameter"><ogc:Literal>outputBBOX</ogc:Literal>
              <ogc:Function name="env"><ogc:Literal>wms_bbox</ogc:Literal></ogc:Function>
            </ogc:Function>
            <ogc:Function name="parameter"><ogc:Literal>outputWidth</ogc:Literal>
              <ogc:Function name="env"><ogc:Literal>wms_width</ogc:Literal></ogc:Function>
            </ogc:Function>
            <ogc:Function name="parameter"><ogc:Literal>outputHeight</ogc:Literal>
              <ogc:Function name="env"><ogc:Literal>wms_height</ogc:Literal></ogc:Function>
            </ogc:Function>
          </ogc:Function>
        </Transformation>
        <Rule>
          <RasterSymbolizer>
            <Geometry><ogc:PropertyName>geom</ogc:PropertyName></Geometry>
            <Opacity>0.7</Opacity>
            <ColorMap type="ramp">
              <ColorMapEntry color="#FFFFFF" quantity="0" opacity="0"/>
              <ColorMapEntry color="#F2C36B" quantity="0.1" opacity="0.5"/>
              <ColorMapEntry color="#D97A1F" quantity="0.4" opacity="0.8"/>
              <ColorMapEntry color="#B3261E" quantity="1.0" opacity="0.9"/>
            </ColorMap>
          </RasterSymbolizer>
        </Rule>
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
