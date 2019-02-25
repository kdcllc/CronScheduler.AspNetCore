using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using System;

namespace Microsoft.Extensions.DependencyInjection
{
    public static class OptionsConfigurationServiceCollectionExtensions
    {
        /// <summary>
        /// Registers a configuration instance which TOptions will bind against without passing <see cref="IConfiguration"/> into registration.
        /// </summary>
        /// <typeparam name="TConfigureType"></typeparam>
        /// <typeparam name="TOptions"></typeparam>
        /// <param name="services"></param>
        /// <param name="sectionName">The Configuration Section Name from where to retrieve the values from.</param>
        /// <returns></returns>
        public static IServiceCollection Configure<TConfigureType, TOptions>(
           this IServiceCollection services,
           string sectionName)
           where TConfigureType : class
           where TOptions : class, new()
        {
            return services.Configure<TConfigureType, TOptions>(sectionName, Options.Options.DefaultName, _ => { });
        }

        /// <summary>
        /// Registers a configuration instance which TOptions will bind against without passing <see cref="IConfiguration"/> into registration.
        /// In addition adds the singelton of the {TOptions}.
        /// https://github.com/aspnet/Extensions/blob/299af9e32ba790dbfe8cfdf99b441766d7b0f6b6/src/Options/ConfigurationExtensions/src/OptionsConfigurationServiceCollectionExtensions.cs#L58
        /// </summary>
        /// <typeparam name="TConfigureType">The type of the object that configuration provider has entry for.</typeparam>
        /// <typeparam name="TOptions">The type of the option object.</typeparam>
        /// <param name="services">The <see cref="IServiceCollection"/> instance.</param>
        /// <param name="sectionName">The Configuration Section Name from where to retrieve the values from.</param>
        /// <param name="optionName">The named option name.</param>
        /// <param name="configureBinder">The <see cref="ConfigurationBinder"/>.</param>
        /// <returns></returns>
        public static IServiceCollection Configure<TConfigureType, TOptions>(
            this IServiceCollection services,
            string sectionName,
            string optionName,
            Action<BinderOptions> configureBinder)
            where TConfigureType : class
            where TOptions : class, new()
        {
            if (services == null)
            {
                throw new ArgumentNullException(nameof(services));
            }

            if (string.IsNullOrEmpty(sectionName))
            {
                throw new ArgumentNullException(nameof(sectionName));
            }

            services.AddOptions();

            services.AddSingleton<IOptionsChangeTokenSource<TOptions>>((sp) => {
                var config = sp.GetRequiredService<IConfiguration>();
                var section = config.GetSection(sectionName).GetSection(typeof(TConfigureType).Name);

                return new ConfigurationChangeTokenSource<TOptions>(optionName, section);
            });

            services.AddSingleton<IConfigureOptions<TOptions>>(sp =>
            {
                var config = sp.GetRequiredService<IConfiguration>();
                var section = config.GetSection(sectionName).GetSection(typeof(TConfigureType).Name);

                return new NamedConfigureFromConfigurationOptions<TOptions>(optionName, section, configureBinder);
            });

            services.AddSingleton(resolver => resolver.GetRequiredService<IOptions<TOptions>>().Value);

            return services;
        }
    }
}
