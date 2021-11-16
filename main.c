#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <mustach-jansson.h>
#include <md4c-html.h>
#include <jansson.h>
#include <CException.h>
#include <sds.h>

#define _unused_ __attribute__((unused))
#define _cleanup_(x) __attribute__((__cleanup__(x)))
#define xmalloc(size) verbose_xmalloc(size, __FILE__, __LINE__)
#define xrealloc(size) verbose_xrealloc(ptr, size, __FILE__, __LINE__)
#define LOG(n, ...) \
	do { \
		fprintf(n, "%s:%d: ", __FILE__, __LINE__); \
		fprintf(n, __VA_ARGS__); \
		fprintf(n, "\n"); \
	} while(0)
#define THROW_WITH_ERRNO() \
	do { \
		jakski_error_line = __LINE__; \
		jakski_error_file = __FILE__; \
		jakski_error = errno; \
		Throw(JAKSKI_ERROR_ERRNO); \
	} while(0)
#define THROW(e) \
	do { \
		jakski_error_line = __LINE__; \
		jakski_error_file = __FILE__; \
		Throw(e); \
	} while(0)
#define THROW_WITH_MESSAGE(m) \
	do { \
		jakski_error_line = __LINE__; \
		jakski_error_file = __FILE__; \
		jakski_error_message = m; \
		Throw(JAKSKI_ERROR_MESSAGE); \
	} while(0)

enum jakski_blog_error {
	JAKSKI_ERROR,
	JAKSKI_ERROR_CONFIG,
	JAKSKI_ERROR_ERRNO,
	JAKSKI_ERROR_MESSAGE,
};

int jakski_error = 0;
int jakski_error_line = 0;
const char *jakski_error_file = NULL;
const char *jakski_error_message = NULL;

void print_error(enum jakski_blog_error error) {
	const char *error_message = NULL;
	switch (error) {
		case JAKSKI_ERROR_ERRNO:
			error_message = strerror(jakski_error);
			break;
		case JAKSKI_ERROR:
			error_message = "Fatal error";
			break;
		case JAKSKI_ERROR_CONFIG:
			error_message = "Bad configuration";
			break;
		case JAKSKI_ERROR_MESSAGE:
			error_message = jakski_error_message;
			break;
		default:
			error_message = "Unknown error";
			break;
	}
	fprintf(
		stderr,
		"%s:%d: %s\n",
		jakski_error_file,
		jakski_error_line,
		error_message
	);
}

_unused_ static inline void *verbose_xmalloc(size_t size, const char *src, int line) {
	void *r = malloc(size);
	if (r == NULL) {
		THROW_WITH_MESSAGE("Failed to allocate memory");
	}
	return r;
}

_unused_ static inline void *verbose_xrealloc(void *ptr, size_t size, const char *src, int line) {
	void *r = realloc(ptr, size);
	if (r == NULL && size != 0) {
		THROW_WITH_MESSAGE("Failed to reallocate memory");
	}
	return r;
}

char *read_file(const char *path, long *file_size)
{
	FILE *src_file = fopen(path, "r");
	if (src_file == NULL) {
		THROW_WITH_ERRNO();
	}
	if (fseek(src_file, 0, SEEK_END) == -1){
		THROW_WITH_ERRNO();
	}
	*file_size = ftell(src_file);
	if (*file_size == -1) {
		THROW_WITH_ERRNO();
	}
	if (fseek(src_file, 0, SEEK_SET) == -1) {
		THROW_WITH_ERRNO();
	}
	char *content = xmalloc(*file_size);
	fread(content, 1, *file_size, src_file);
	if (ferror(src_file) != 0) {
		THROW_WITH_MESSAGE("Failed to read from source file");
	}
	if (fclose(src_file) == EOF) {
		THROW_WITH_ERRNO();
	}
	return content;
}

static void process_markdown(const MD_CHAR *text, MD_SIZE size, void *userdata)
{
	sds *output = (sds *) userdata;
	*output = sdscatlen(*output, text, size);
	if (*output == NULL) {
		THROW_WITH_MESSAGE("Failed to extend buffer");
	}
}

sds render_markdown(const char *path)
{
	long file_size = 0;
	char *content = read_file(path, &file_size);
	sds output;
	if ((output = sdsempty()) == NULL) {
		THROW_WITH_MESSAGE("Failed to create string");
	}
	unsigned parser_flags =
		MD_FLAG_COLLAPSEWHITESPACE
		| MD_FLAG_TABLES
		| MD_FLAG_STRIKETHROUGH
		| MD_FLAG_UNDERLINE
		| MD_FLAG_TASKLISTS;
	if (md_html(content, file_size, process_markdown, &output, parser_flags, 0) == -1) {
		THROW_WITH_MESSAGE("Failed to parse markdown");
	}
	free(content);
	return output;
}

int main(int argc, char **argv)
{
	json_t *cfg = NULL;
	json_error_t json_error;
	CEXCEPTION_T error;

	Try {
		if (argc != 2) {
			THROW_WITH_MESSAGE("Exactly one argument required: configuration file");
		}
		if ((cfg = json_load_file(argv[1], 0, &json_error)) == NULL) {
			THROW_WITH_MESSAGE("Failed to read configuration file");
		}
		json_t *pages = json_object_get(cfg, "pages");
		if (pages == NULL || !json_is_array(pages))
			THROW(JAKSKI_ERROR_CONFIG);
		size_t page_index;
		json_t *page;
		json_array_foreach(pages, page_index, page) {
			json_t *page_parameters = json_object();
			if (page_parameters == NULL)
				THROW_WITH_MESSAGE("Failed to create page parameters");

			if (json_object_set(page_parameters, "page", page) == -1)
				THROW_WITH_MESSAGE("Failed to set page parameters");

			if (json_object_set(page_parameters, "global", cfg) == -1)
				THROW_WITH_MESSAGE("Faile to set page global parameters");

			const char *output_path = json_string_value(json_object_get(page, "output"));
			if (output_path == NULL) THROW(JAKSKI_ERROR_CONFIG);

			const char *template_path = json_string_value(json_object_get(page, "template"));
			if (template_path == NULL) THROW(JAKSKI_ERROR_CONFIG);

			FILE *output_file = fopen(output_path, "w");
			if (output_file == NULL) THROW_WITH_ERRNO();

			CEXCEPTION_T error;
			Try {
				sds content = NULL;
				const char *markdown_path = json_string_value(json_object_get(page, "markdown"));
				if (markdown_path != NULL) {
					content = render_markdown(markdown_path);
					if (json_object_set_new(page_parameters, "content", json_string(content)) == -1)
						THROW_WITH_MESSAGE("Failed to set content on page parameters");
					sdsfree(content);
				}
			} Catch(error) {
				print_error(error);
				THROW_WITH_MESSAGE("Failed to render markdown");
			}

			char *template = NULL;
			Try {
				long template_size = 0;
				template = read_file(template_path, &template_size);
				if (mustach_jansson_file(
					template,
					template_size,
					page_parameters,
					Mustach_With_AllExtensions,
					output_file
				) == -1)
				{
					THROW(JAKSKI_ERROR);
				}
			} Catch(error) {
				print_error(error);
				THROW_WITH_MESSAGE("Failed to render template");
			}

			if (fclose(output_file) == EOF) {
				THROW_WITH_MESSAGE("Failed to close output file");
			}
			json_decref(page_parameters);
			free(template);
		}
	} Catch(error) {
		print_error(error);
		exit(EXIT_FAILURE);
	}

	json_decref(cfg);
	return 0;
}
