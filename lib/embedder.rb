require "informers"

class Embedder
  VECTOR_SIZE = 768

  def initialize(model_name: "mochiya98/ruri-v3-310m-onnx")
    @pipeline = Informers.pipeline("feature-extraction", model_name)
  end

  def embed(text)
    result = @pipeline.(text, model_output: "token_embeddings", pooling: "mean", normalize: true)
    result.flatten.map(&:to_f)
  end
end
