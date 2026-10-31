use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, Data, DeriveInput, Fields, GenericArgument, LitStr, PathArguments, Type};

fn last_type_name(ty: &Type) -> Option<String> {
    let Type::Path(path) = ty else { return None };
    path.path.segments.last().map(|segment| segment.ident.to_string())
}

fn inner_type_name(ty: &Type) -> Option<String> {
    let Type::Path(path) = ty else { return None };
    let segment = path.path.segments.last()?;
    let PathArguments::AngleBracketed(args) = &segment.arguments else { return None };
    args.args.iter().find_map(|arg| {
        let GenericArgument::Type(inner) = arg else { return None };
        last_type_name(inner)
    })
}

fn clap_default(attrs: &[syn::Attribute]) -> Option<LitStr> {
    let mut result = None;
    for attr in attrs.iter().filter(|attr| attr.path().is_ident("clap")) {
        let _ = attr.parse_nested_meta(|meta| {
            if meta.path.is_ident("default_value") {
                result = Some(meta.value()?.parse()?);
            }
            Ok(())
        });
    }
    result
}

fn is_flatten(attrs: &[syn::Attribute]) -> bool {
    attrs.iter().filter(|attr| attr.path().is_ident("clap")).any(|attr| {
        let mut found = false;
        let _ = attr.parse_nested_meta(|meta| {
            if meta.path.is_ident("flatten") {
                found = true;
            }
            Ok(())
        });
        found
    })
}

#[proc_macro_derive(Parser, attributes(clap))]
pub fn derive_parser(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = input.ident;
    let Data::Struct(data) = input.data else {
        return syn::Error::new_spanned(name, "Parser shim only supports structs")
            .to_compile_error()
            .into();
    };
    let Fields::Named(fields) = data.fields else {
        return syn::Error::new_spanned(name, "Parser shim requires named fields")
            .to_compile_error()
            .into();
    };

    let initializers = fields.named.into_iter().map(|field| {
        let field_name = field.ident.expect("named field");
        let field_name_text = field_name.to_string();
        let ty = field.ty;
        let expr = if is_flatten(&field.attrs) {
            quote!(<#ty as clap::Parser>::parse_from([""]))
        } else if let Some(default) = clap_default(&field.attrs) {
            quote!(clap::parse_default::<#ty>(#default))
        } else if matches!(field_name_text.as_str(), "batch" | "inv_candidates") {
            quote!(1)
        } else {
            match last_type_name(&ty).as_deref() {
                Some("bool") => quote!(false),
                Some("Option") => quote!(None),
                Some("Vec") => quote!(Vec::new()),
                Some("String") => quote!(String::new()),
                Some("FusedLambdaTags") => quote!(clap::parse_default::<#ty>("")),
                Some(_) if inner_type_name(&ty).is_some() => quote!(Default::default()),
                _ => quote!(Default::default()),
            }
        };
        quote!(#field_name: #expr)
    });

    quote! {
        impl clap::Parser for #name {
            fn parse_from<I, T>(_args: I) -> Self
            where
                I: IntoIterator<Item = T>,
                T: Into<std::ffi::OsString> + Clone,
            {
                Self { #(#initializers),* }
            }
        }
    }
    .into()
}

#[proc_macro_derive(ArgEnum, attributes(clap))]
pub fn derive_arg_enum(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = input.ident;
    let Data::Enum(data) = input.data else {
        return syn::Error::new_spanned(name, "ArgEnum shim only supports enums")
            .to_compile_error()
            .into();
    };

    let arms = data.variants.into_iter().map(|variant| {
        let variant_name = variant.ident;
        let raw = variant_name.to_string();
        let mut kebab = String::new();
        for (index, ch) in raw.chars().enumerate() {
            if ch.is_uppercase() && index > 0 {
                kebab.push('-');
            }
            kebab.extend(ch.to_lowercase());
        }
        quote!(#kebab => Ok(Self::#variant_name))
    });

    quote! {
        impl std::str::FromStr for #name {
            type Err = String;
            fn from_str(value: &str) -> Result<Self, Self::Err> {
                match value {
                    #(#arms,)*
                    _ => Err(format!("unsupported enum value: {value}")),
                }
            }
        }
    }
    .into()
}
