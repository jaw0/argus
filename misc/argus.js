// Copyright (c) 2007 by Jeff Weisberg
// Author: Jeff Weisberg <argus @ tcp4me.com>
// Created: 2007-Jan-10 23:05 (EST)
// Function: argus javascript - for popups
//
// $Id: argus.js,v 1.6 2011/11/03 02:13:40 jaw Exp $

function arjax_display(name,dpy){
    var elem = document.getElementById( name );
    if(elem){
	elem.style.display = dpy;
    }
}

function annotate_show(){
    arjax_display('annotatediv', 'block');
    document.annotateform.text.focus();
    return false;
}

function annotate_hide(){
    arjax_display('annotatediv', 'none');
    return false;
}

function override_show(){
    arjax_display('overridediv', 'block');
    document.overrideform.text.focus();
    return false;
}

function override_hide(){
    arjax_display('overridediv', 'none');
    return false;
}

window.onload = function(){

    var hide = document.getElementById('arguserror_js37');
    if( hide ) hide.style.display = 'none';

    var ann = document.getElementById('button_annotate');
    if( ann ) ann.onclick = annotate_show;

    var ancn = document.getElementById('annotatecancel');
    if( ancn ) ancn.onclick = annotate_hide;

    var ov = document.getElementById('button_override');
    if( ov ) ov.onclick = override_show;

    var rmov = document.getElementById('overridecancel');
    if( rmov ) rmov.onclick = override_hide;

};

