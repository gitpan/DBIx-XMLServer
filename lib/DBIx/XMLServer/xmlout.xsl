<?xml version="1.0" encoding="utf-8"?>
<!-- $Id: xmlout.xsl,v 1.3 2003/11/03 21:54:08 mjb47 Exp $ -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0"
  xmlns:sql="http://boojum.org.uk/NS/XMLServer">

  <xsl:output method="xml"/>
  <xsl:strip-space elements="*"/>

  <!-- Cut out the sql:template element -->
  <xsl:template match="sql:template">
    <xsl:apply-templates/>
  </xsl:template>  

  <!-- Remove the template record entirely -->
  <xsl:template match="sql:record"/>

  <!-- Remove elements with a <sql:null type='omit'> child -->
  <xsl:template match="*[sql:null/@type='omit']"/>

  <!-- Process <sql:null type='nil'> elements (but not within 
       <sql:attribute> elements - they'll be caught elsewhere -->
  <xsl:template match="sql:null[@type='nil']">
    <xsl:attribute name="nil" 
      namespace="http://www.w3.org/2001/XMLSchema-instance">
      <xsl:text>true</xsl:text>
    </xsl:attribute>
  </xsl:template>

  <!-- Remove <sql:null type='empty'> elements -->
  <xsl:template match="sql:null[@type='empty']"/>

  <!-- Remove elements as per sql:omit attribute -->
  <xsl:template match="*[@sql:omit='true']">
    <xsl:variable name="content">
      <xsl:apply-templates mode="check-omit" select="node()"/>
    </xsl:variable>
    <xsl:if test="string($content)">
      <xsl:copy>
        <xsl:apply-templates select="@*|node()"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>

  <xsl:template match="*[sql:null/@type='omit']" mode="check-omit" 
    priority="2"/>

  <xsl:template match="*[not(@sql:omit='true')]" mode="check-omit">
    <xsl:value-of select="name()"/>
  </xsl:template>

  <!-- Process <sql:attribute> elements -->
  <xsl:template match="sql:attribute[not(sql:null/@type='omit')]">
    <xsl:attribute name="{@name}">
      <xsl:value-of select="."/>
    </xsl:attribute>
  </xsl:template>

  <!-- ...and those with a 'nil' null value inside them -->
  <xsl:template match="sql:attribute[sql:null/@type='nil']" priority="2">
    <xsl:attribute name="nil" 
      namespace="http://www.w3.org/2001/XMLSchema-instance">
      <xsl:text>true</xsl:text>
    </xsl:attribute>
  </xsl:template>

  <!-- Don't copy attributes corresponding to <sql:attribute> elements -->
  <xsl:template match="@*[../sql:attribute/@name=name(current())]"/>

  <!-- Don't copy sql:* attributes -->
  <xsl:template match="@sql:*"/>

  <!-- Do copy everything else -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>
